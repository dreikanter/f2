require "test_helper"

class TokenGroupsRefreshTimeoutJobTest < ActiveJob::TestCase
  test "#queue_name should use the dedicated timeout queue" do
    assert_equal "timeouts", TokenGroupsRefreshTimeoutJob.queue_name
  end

  test "#perform should time out the run idempotently" do
    detail = create(:access_token_detail)
    run = create(:operation_run, subject: detail, kind: :groups_refresh)

    TokenGroupsRefreshTimeoutJob.perform_now(run)

    assert_predicate run.reload, :timed_out?
    assert_predicate detail.reload, :groups_refresh_failed?
    finished_at = run.finished_at

    TokenGroupsRefreshTimeoutJob.perform_now(run)

    assert_equal finished_at, run.reload.finished_at
  end

  test "#perform should do nothing when the run was superseded" do
    detail = create(:access_token_detail)
    run = create(:operation_run, subject: detail, kind: :groups_refresh,
                                 status: :superseded, finished_at: Time.current)

    TokenGroupsRefreshTimeoutJob.perform_now(run)

    assert_predicate run.reload, :superseded?
    assert_not_predicate detail.reload, :groups_refresh_failed?
  end
end
