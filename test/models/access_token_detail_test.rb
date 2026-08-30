require "test_helper"

class AccessTokenDetailTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  RUN_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
  NEXT_RUN_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

  setup { clear_enqueued_jobs }

  test "#group_names should extract usernames from managed groups" do
    groups = [{ "username" => "group1" }, { "username" => "group2" }, { "id" => "no-name" }]
    detail = build(:access_token_detail, managed_groups: groups)
    assert_equal %w[group1 group2], detail.group_names
  end

  test "#groups_refresh_running? should require complete run metadata" do
    assert_not build(:access_token_detail).groups_refresh_running?
    assert_not build(:access_token_detail, groups_refresh_state: :running,
                                           groups_refresh_requested_at: Time.current).groups_refresh_running?
    assert_not build(:access_token_detail, groups_refresh_state: :running,
                                           groups_refresh_run_id: RUN_ID).groups_refresh_running?

    detail = build(:access_token_detail, groups_refresh_state: :running,
                                         groups_refresh_requested_at: Time.current,
                                         groups_refresh_run_id: RUN_ID)
    assert detail.groups_refresh_running?
    assert detail.groups_refresh_running?(run_id: RUN_ID)
    assert_not detail.groups_refresh_running?(run_id: NEXT_RUN_ID)
  end

  test "#groups_refresh_run_id should use the native UUID type" do
    assert_equal :uuid, AccessTokenDetail.type_for_attribute("groups_refresh_run_id").type
  end

  test "#start_groups_refresh! should persist and schedule a worker and timeout for one run" do
    detail = build(:access_token_detail)

    freeze_time do
      SecureRandom.stub(:uuid, RUN_ID) do
        assert_enqueued_with(job: TokenGroupsRefreshTimeoutJob,
                             at: AccessTokenDetail::GROUPS_REFRESH_TIMEOUT_AFTER.from_now) do
          assert_enqueued_with(job: TokenGroupsRefreshJob, args: [detail.access_token, RUN_ID]) do
            detail.start_groups_refresh!
          end
        end
      end
    end

    assert detail.persisted?
    assert detail.groups_refresh_running?(run_id: RUN_ID)
    assert_enqueued_with(job: TokenGroupsRefreshTimeoutJob, args: [detail.id, RUN_ID])
  end

  test "#complete_groups_refresh! should store stringified groups and clear the run" do
    detail = create(:access_token_detail, groups_refresh_state: :running,
                                          groups_refresh_requested_at: Time.current,
                                          groups_refresh_run_id: RUN_ID)

    assert detail.complete_groups_refresh!([{ username: "newgroup", screenName: "New Group" }], run_id: RUN_ID)

    assert_not detail.groups_refresh_running?
    assert_not detail.groups_refresh_failed?
    assert_nil detail.groups_refresh_run_id
    assert_equal [{ "username" => "newgroup", "screenName" => "New Group" }], detail.managed_groups
    assert_equal "testuser", detail.reload.freefeed_user_info["username"]
  end

  test "#complete_groups_refresh! should ignore a superseded run" do
    detail = create(:access_token_detail, managed_groups: [{ username: "current" }],
                                          groups_refresh_state: :running,
                                          groups_refresh_requested_at: Time.current,
                                          groups_refresh_run_id: NEXT_RUN_ID)
    original_attributes = detail.attributes.slice(
      "managed_groups", "groups_refresh_state", "groups_refresh_requested_at", "groups_refresh_run_id", "updated_at"
    )

    assert_not detail.complete_groups_refresh!([{ username: "stale" }], run_id: RUN_ID)

    assert_equal original_attributes, detail.reload.attributes.slice(*original_attributes.keys)
  end

  test "#fail_groups_refresh! should ignore a superseded run" do
    detail = create(:access_token_detail, groups_refresh_state: :running,
                                          groups_refresh_requested_at: Time.current,
                                          groups_refresh_run_id: NEXT_RUN_ID)
    original_attributes = detail.attributes.slice(
      "groups_refresh_state", "groups_refresh_requested_at", "groups_refresh_run_id", "updated_at"
    )

    assert_not detail.fail_groups_refresh!(run_id: RUN_ID)

    assert_equal original_attributes, detail.reload.attributes.slice(*original_attributes.keys)
  end

  test "#fail_groups_refresh! should fail and clear the matching run" do
    detail = create(:access_token_detail, groups_refresh_state: :running,
                                          groups_refresh_requested_at: Time.current,
                                          groups_refresh_run_id: RUN_ID)

    assert detail.fail_groups_refresh!(run_id: RUN_ID)

    assert_not detail.groups_refresh_running?
    assert detail.groups_refresh_failed?
    assert_nil detail.groups_refresh_run_id
  end

  test "#timeout_groups_refresh! should rotate the run and allow an immediate restart" do
    detail = create(:access_token_detail, groups_refresh_state: :running,
                                          groups_refresh_requested_at: Time.current,
                                          groups_refresh_run_id: RUN_ID)

    SecureRandom.stub(:uuid, NEXT_RUN_ID) { detail.timeout_groups_refresh!(run_id: RUN_ID) }

    assert detail.groups_refresh_failed?
    assert_equal NEXT_RUN_ID, detail.groups_refresh_run_id

    restarted_run_id = SecureRandom.uuid
    SecureRandom.stub(:uuid, restarted_run_id) { detail.start_groups_refresh! }
    assert detail.groups_refresh_running?(run_id: restarted_run_id)
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

  test "should reject an unknown refresh state" do
    detail = create(:access_token_detail)

    assert_raises ArgumentError do
      detail.update!(groups_refresh_state: "bogus")
    end
  end

  test "should reject an unknown refresh state at the database level" do
    detail = create(:access_token_detail)

    error = assert_raises ActiveRecord::StatementInvalid do
      detail.class.connection.execute(
        AccessTokenDetail.sanitize_sql(
          ["UPDATE access_token_details SET groups_refresh_state = 99 WHERE id = ?", detail.id]
        )
      )
    end

    assert_match(/groups_refresh_state_valid/, error.message)
  end
end
