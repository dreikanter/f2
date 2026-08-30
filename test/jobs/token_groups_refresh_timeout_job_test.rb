require "test_helper"

class TokenGroupsRefreshTimeoutJobTest < ActiveJob::TestCase
  RUN_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
  NEXT_RUN_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

  test "#queue_name should use the dedicated timeout queue" do
    assert_equal "timeouts", TokenGroupsRefreshTimeoutJob.queue_name
  end

  test "#perform should fail the matching run, rotate its id, and be idempotent" do
    detail = create(:access_token_detail, groups_refresh_state: :running,
                                          groups_refresh_requested_at: Time.current,
                                          groups_refresh_run_id: RUN_ID)

    SecureRandom.stub(:uuid, NEXT_RUN_ID) do
      TokenGroupsRefreshTimeoutJob.perform_now(detail.id, RUN_ID)
    end

    assert detail.reload.groups_refresh_failed?
    assert_equal NEXT_RUN_ID, detail.groups_refresh_run_id

    timed_out_attributes = detail.attributes.slice(
      "groups_refresh_state", "groups_refresh_requested_at", "groups_refresh_run_id", "updated_at"
    )
    TokenGroupsRefreshTimeoutJob.perform_now(detail.id, RUN_ID)
    assert_equal timed_out_attributes, detail.reload.attributes.slice(*timed_out_attributes.keys)
  end

  test "#perform should do nothing when the run was superseded" do
    detail = create(:access_token_detail, groups_refresh_state: :running,
                                          groups_refresh_requested_at: Time.current,
                                          groups_refresh_run_id: NEXT_RUN_ID)
    original_attributes = detail.attributes.slice(
      "groups_refresh_state", "groups_refresh_requested_at", "groups_refresh_run_id", "updated_at"
    )

    TokenGroupsRefreshTimeoutJob.perform_now(detail.id, RUN_ID)

    assert_equal original_attributes, detail.reload.attributes.slice(*original_attributes.keys)
  end

  test "#perform should do nothing when the detail was deleted" do
    detail = create(:access_token_detail)
    detail.destroy!

    assert_nothing_raised { TokenGroupsRefreshTimeoutJob.perform_now(detail.id, RUN_ID) }
  end
end
