require "test_helper"

class TokenGroupsRefreshJobTest < ActiveJob::TestCase
  def access_token
    @access_token ||= create(:access_token, :active)
  end

  def detail
    @detail ||= create(:access_token_detail, access_token: access_token).tap(&:begin_groups_refresh!)
  end

  def stub_managed_groups(status: 200, body: [{ username: "newgroup" }].to_json)
    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .to_return(status: status, body: body)
  end

  test "#perform should update the stored groups and clear the running marker" do
    detail
    stub_managed_groups

    TokenGroupsRefreshJob.perform_now(access_token)

    detail.reload
    assert_equal ["newgroup"], detail.group_names
    assert detail.managed_groups.first.key?("screen_name")
    assert_not detail.groups_refresh_running?
    assert_not detail.groups_refresh_failed?
  end

  test "#perform should refresh the cached group names" do
    detail
    stub_managed_groups

    cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stub(:cache, cache) do
      TokenGroupsRefreshJob.perform_now(access_token)
    end

    assert_equal ["newgroup"], cache.read(access_token.groups_cache_key)
  end

  test "#perform should do nothing when the token has no detail" do
    TokenGroupsRefreshJob.perform_now(access_token)

    assert_not_requested :get, /managedGroups/
  end

  test "#perform should mark the refresh failed for an inactive token" do
    detail
    access_token.inactive!

    TokenGroupsRefreshJob.perform_now(access_token)

    assert detail.reload.groups_refresh_failed?
    assert_not_requested :get, /managedGroups/
  end

  test "#perform should hand an unauthorized token to validation and mark the refresh failed" do
    detail
    stub_managed_groups(status: 401, body: "Unauthorized")

    assert_enqueued_with(job: TokenValidationJob, args: [access_token]) do
      TokenGroupsRefreshJob.perform_now(access_token)
    end

    assert detail.reload.groups_refresh_failed?
  end

  test "#perform should report unexpected errors and mark the refresh failed" do
    detail
    stub_managed_groups(status: 500, body: "Internal Server Error")

    reported = nil
    Rails.error.stub(:report, ->(error, **) { reported = error }) do
      TokenGroupsRefreshJob.perform_now(access_token)
    end

    assert_kind_of FreefeedClient::Error, reported
    assert detail.reload.groups_refresh_failed?
  end

  test "#perform should reschedule when the local rate limit is exhausted" do
    detail
    drain_freefeed(access_token.rate_limit_subject, :get, remaining: 0)

    assert_enqueued_with(job: TokenGroupsRefreshJob) do
      TokenGroupsRefreshJob.perform_now(access_token)
    end

    assert detail.reload.groups_refresh_running?
    assert_not_requested :get, /managedGroups/
  end
end
