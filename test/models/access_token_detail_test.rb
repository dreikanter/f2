require "test_helper"

class AccessTokenDetailTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  test "#group_names should extract usernames from managed groups" do
    groups = [{ "username" => "group1" }, { "username" => "group2" }, { "id" => "no-name" }]
    detail = build(:access_token_detail, managed_groups: groups)

    assert_equal %w[group1 group2], detail.group_names
  end

  test "#groups_refresh_running? should reflect the active run" do
    detail = create(:access_token_detail)

    assert_not detail.groups_refresh_running?

    create(:operation_run, subject: detail, kind: :groups_refresh)

    assert detail.groups_refresh_running?
  end

  test "#groups_refresh_running? should treat an old run as abandoned" do
    detail = create(:access_token_detail)
    create(:operation_run, subject: detail, kind: :groups_refresh,
                           started_at: AccessTokenDetail::GROUPS_REFRESH_STALE_AFTER.ago)

    travel 1.minute do
      assert_not detail.groups_refresh_running?
    end
  end

  test "#groups_refresh_failed? should reflect the latest terminal run" do
    detail = create(:access_token_detail)
    create(:operation_run, subject: detail, kind: :groups_refresh, status: :failed, finished_at: Time.current)

    assert detail.groups_refresh_failed?

    create(:operation_run, subject: detail, kind: :groups_refresh, status: :succeeded, finished_at: Time.current)

    assert_not detail.groups_refresh_failed?
  end

  test "#start_groups_refresh! should persist and schedule a worker and timeout for one run" do
    detail = build(:access_token_detail)

    freeze_time do
      detail.start_groups_refresh!
      run = detail.active_operation_run(:groups_refresh)

      assert_enqueued_with(job: TokenGroupsRefreshJob, args: [run])
      assert_enqueued_with(
        job: TokenGroupsRefreshTimeoutJob,
        args: [run],
        at: AccessTokenDetail::GROUPS_REFRESH_TIMEOUT_AFTER.from_now
      )
    end

    assert detail.persisted?
    assert detail.groups_refresh_running?
  end

  test "#start_groups_refresh! should supersede an older run" do
    detail = create(:access_token_detail)
    old_run = create(:operation_run, subject: detail, kind: :groups_refresh)

    detail.start_groups_refresh!

    assert_predicate old_run.reload, :superseded?
    assert_not_equal old_run, detail.active_operation_run(:groups_refresh)
  end

  test "#replace_managed_groups! should store stringified groups" do
    detail = create(:access_token_detail)

    detail.replace_managed_groups!([{ username: "newgroup", screenName: "New Group" }])

    assert_equal [{ "username" => "newgroup", "screenName" => "New Group" }], detail.managed_groups
  end

  test "#replace_managed_groups_and_finish_refresh! should settle the active refresh" do
    detail = create(:access_token_detail)
    run = create(:operation_run, subject: detail, kind: :groups_refresh)

    detail.replace_managed_groups_and_finish_refresh!([{ username: "newgroup" }])

    assert_predicate run.reload, :succeeded?
    assert_not detail.groups_refresh_running?
    assert_equal [{ "username" => "newgroup" }], detail.reload.managed_groups
  end

  test ".groups_refresh_polling_max_polls should preserve the polling interval and timeout budget" do
    assert_equal 2500, AccessTokenDetail::GROUPS_REFRESH_POLLING_INTERVAL_MS
    assert_equal 85.seconds, AccessTokenDetail::GROUPS_REFRESH_TIMEOUT_AFTER
    assert_equal 36, AccessTokenDetail.groups_refresh_polling_max_polls

    final_poll_at = (AccessTokenDetail.groups_refresh_polling_max_polls - 1) *
                    AccessTokenDetail::GROUPS_REFRESH_POLLING_INTERVAL_MS
    assert_equal AccessTokenDetail::GROUPS_REFRESH_POLLING_INTERVAL_MS,
                 final_poll_at - AccessTokenDetail::GROUPS_REFRESH_TIMEOUT_AFTER.in_milliseconds
  end
end
