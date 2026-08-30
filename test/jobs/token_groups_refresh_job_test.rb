require "test_helper"

class TokenGroupsRefreshJobTest < ActiveJob::TestCase
  def access_token
    @access_token ||= create(:access_token, :active)
  end

  def detail
    @detail ||= create(:access_token_detail, access_token: access_token)
  end

  def refresh_run
    @refresh_run ||= create(:operation_run, subject: detail, kind: :groups_refresh)
  end

  def stub_managed_groups(status: 200, body: [{ username: "newgroup" }].to_json)
    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .to_return(status: status, body: body)
  end

  test "#perform should update the stored groups and clear the running marker" do
    detail
    stub_managed_groups

    TokenGroupsRefreshJob.perform_now(refresh_run)

    detail.reload
    assert_equal ["newgroup"], detail.group_names
    assert detail.managed_groups.first.key?("screen_name")
    assert_not detail.groups_refresh_running?
    assert_not detail.groups_refresh_failed?
    assert_predicate refresh_run.reload, :succeeded?
  end

  test "#perform should refresh the cached group names" do
    detail
    stub_managed_groups

    cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stub(:cache, cache) do
      TokenGroupsRefreshJob.perform_now(refresh_run)
    end

    assert_equal ["newgroup"], cache.read(access_token.groups_cache_key)
  end

  test "#perform should mark the refresh failed for an inactive token" do
    detail
    access_token.inactive!

    TokenGroupsRefreshJob.perform_now(refresh_run)

    assert detail.reload.groups_refresh_failed?
    assert_not_requested :get, /managedGroups/
  end

  test "#perform should hand an unauthorized token to validation and mark the refresh failed" do
    detail
    stub_managed_groups(status: 401, body: "Unauthorized")

    assert_enqueued_with(job: TokenValidationJob) do
      TokenGroupsRefreshJob.perform_now(refresh_run)
    end

    validation = access_token.active_operation_run(:validation)
    assert_enqueued_with(job: TokenValidationJob, args: [validation])

    assert detail.reload.groups_refresh_failed?
  end

  test "#perform should report unexpected errors and mark the refresh failed" do
    detail
    stub_managed_groups(status: 500, body: "Internal Server Error")

    reported = nil
    Rails.error.stub(:report, ->(error, **) { reported = error }) do
      TokenGroupsRefreshJob.perform_now(refresh_run)
    end

    assert_kind_of FreefeedClient::Error, reported
    assert detail.reload.groups_refresh_failed?
  end

  test "#perform should reschedule when the local rate limit is exhausted" do
    detail
    drain_freefeed(access_token.rate_limit_subject, :get, remaining: 0)

    assert_enqueued_with(job: TokenGroupsRefreshJob, args: [refresh_run]) do
      TokenGroupsRefreshJob.perform_now(refresh_run)
    end

    assert detail.reload.groups_refresh_running?
    assert_not_requested :get, /managedGroups/
  end

  test "#perform should reschedule without failing when throttled mid-call" do
    detail
    stub_managed_groups(status: 429, body: "")

    reported = []
    assert_enqueued_with(job: TokenGroupsRefreshJob, args: [refresh_run]) do
      Rails.error.stub(:report, ->(*args, **) { reported << args }) do
        TokenGroupsRefreshJob.perform_now(refresh_run)
      end
    end

    assert_empty reported, "a handled throttle must not be reported as a fault"
    assert detail.reload.groups_refresh_running?
  end

  test "#perform should mark the refresh failed when throttle retries are exhausted" do
    detail
    drain_freefeed(access_token.rate_limit_subject, :get, remaining: 0)

    job = TokenGroupsRefreshJob.new(refresh_run)
    job.executions = RateLimited::MAX_ATTEMPTS

    Rails.error.stub(:report, ->(*, **) { }) do
      assert_no_enqueued_jobs { job.perform_now }
    end

    assert detail.reload.groups_refresh_failed?
    assert_not_requested :get, /managedGroups/
  end

  test "#perform should ignore a timed-out run before fetching groups" do
    detail
    TokenGroupsRefreshTimeoutJob.perform_now(refresh_run)

    TokenGroupsRefreshJob.perform_now(refresh_run)

    assert_not_requested :get, /managedGroups/
    assert detail.reload.groups_refresh_failed?
  end

  test "#perform should not persist or cache a result that returns after timeout" do
    detail
    cache = ActiveSupport::Cache::MemoryStore.new
    cache.write(access_token.groups_cache_key, ["oldgroup"])
    stub_request(:get, "#{access_token.host}/v4/managedGroups").to_return do
      TokenGroupsRefreshTimeoutJob.perform_now(refresh_run)
      { status: 200, body: [{ username: "late-group" }].to_json }
    end

    Rails.stub(:cache, cache) do
      TokenGroupsRefreshJob.perform_now(refresh_run)
    end

    assert_empty detail.reload.group_names
    assert detail.groups_refresh_failed?
    assert_equal ["oldgroup"], cache.read(access_token.groups_cache_key)
  end
end
