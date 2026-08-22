require "test_helper"

class TokenScopesRefreshJobTest < ActiveJob::TestCase
  def access_token
    @access_token ||= create(:access_token, :active, scopes: [])
  end

  def stub_app_token_info(scopes: AccessToken::TOKEN_SCOPES)
    stub_request(:get, "#{access_token.host}/v2/app-tokens/current")
      .to_return(
        status: 200,
        body: { token: { id: "token-1", scopes: scopes } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  test "#perform should record the scopes FreeFeed reports" do
    stub_app_token_info(scopes: ["read-my-info", "manage-posts"])

    TokenScopesRefreshJob.perform_now(access_token)

    assert_equal ["read-my-info", "manage-posts"], access_token.reload.scopes
  end

  test "#perform should record every scope for a session token" do
    stub_request(:get, "#{access_token.host}/v2/app-tokens/current")
      .to_return(status: 400, body: { err: "Not an app token" }.to_json)

    TokenScopesRefreshJob.perform_now(access_token)

    assert_equal AccessToken::TOKEN_SCOPES, access_token.reload.scopes
  end

  test "#perform should leave recorded scopes alone" do
    access_token.update!(scopes: [AccessToken::MANAGE_POSTS_SCOPE])

    TokenScopesRefreshJob.perform_now(access_token)

    assert_not_requested :get, /\/v2\/app-tokens\//
    assert_equal [AccessToken::MANAGE_POSTS_SCOPE], access_token.reload.scopes
  end

  test "#perform should do nothing for a token that is not active" do
    access_token.inactive!

    TokenScopesRefreshJob.perform_now(access_token)

    assert_not_requested :get, /\/v2\/app-tokens\//
    assert_empty access_token.reload.scopes
  end

  test "#perform should send a dead token to validation" do
    stub_request(:get, "#{access_token.host}/v2/app-tokens/current")
      .to_return(status: 401, body: { err: "inactive or expired token" }.to_json)

    assert_enqueued_with(job: TokenValidationJob, args: [access_token]) do
      TokenScopesRefreshJob.perform_now(access_token)
    end

    assert_empty access_token.reload.scopes
    # The status must not change until validation actually runs, or queued
    # publications would fail against a transiently non-active token.
    assert access_token.reload.active?
  end

  test "#perform should reschedule when the local rate limit is exhausted" do
    drain_freefeed(access_token.rate_limit_subject, :get, remaining: 0)

    assert_enqueued_with(job: TokenScopesRefreshJob) do
      TokenScopesRefreshJob.perform_now(access_token)
    end

    assert_not_requested :get, /\/v2\/app-tokens\//
  end

  test "#perform should reschedule when FreeFeed responds with 429" do
    stub_request(:get, "#{access_token.host}/v2/app-tokens/current")
      .to_return(status: 429, headers: { "Retry-After" => "30" })

    assert_enqueued_with(job: TokenScopesRefreshJob) do
      TokenScopesRefreshJob.perform_now(access_token)
    end

    assert_empty access_token.reload.scopes
  end
end
