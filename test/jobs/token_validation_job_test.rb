require "test_helper"

class TokenValidationJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user)
  end

  def start_validation(token = access_token)
    run_id = SecureRandom.uuid
    token.update!(status: :validating, validation_started_at: Time.current, validation_run_id: run_id)
    run_id
  end

  def perform_validation(token = access_token, run_id: start_validation(token))
    TokenValidationJob.perform_now(token, run_id)
  end

  test ".perform_now should reserve three GETs and reschedule when throttled" do
    subject = access_token.rate_limit_subject
    run_id = start_validation

    freeze_time do
      # Two GET tokens is short of validation's cost of 3, so it throttles
      # before any of the GETs goes out.
      drain_freefeed(subject, :get, remaining: 2)

      assert_enqueued_with(job: TokenValidationJob) do
        TokenValidationJob.perform_now(access_token, run_id)
      end
    end

    assert_not_requested :get, "#{access_token.host}/v4/users/whoami"
    assert_not_requested :get, "#{access_token.host}/v2/app-tokens/current"
  end

  test ".perform_now should reset token to pending when throttle retries are exhausted" do
    run_id = start_validation
    subject = access_token.rate_limit_subject

    job = TokenValidationJob.new(access_token, run_id)
    job.executions = RateLimited::MAX_ATTEMPTS

    freeze_time do
      drain_freefeed(subject, :get, remaining: 0)

      Rails.error.stub(:report, ->(*, **) { }) do
        assert_no_enqueued_jobs only: TokenValidationJob do
          job.perform_now
        end
      end
    end

    access_token.reload
    assert access_token.pending?
  end

  test ".perform_now should reschedule without failing when validation is throttled mid-call" do
    run_id = start_validation
    stub_app_token_info
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .to_return(status: 429, headers: { "Retry-After" => "30" })

    reported = []
    assert_enqueued_with(job: TokenValidationJob) do
      Rails.error.stub(:report, ->(*args, **) { reported << args }) do
        TokenValidationJob.perform_now(access_token, run_id)
      end
    end

    assert_empty reported, "a handled throttle must not be reported as a fault"
    assert_not access_token.reload.inactive?, "a throttle must not disable the token"
  end

  test ".perform_now should mark token as active when validation succeeds" do
    stub_successful_freefeed_response

    assert access_token.pending?

    perform_validation

    access_token.reload
    assert access_token.active?
    assert_equal "testuser", access_token.owner
    assert_nil access_token.validation_started_at
    assert_nil access_token.validation_run_id
  end

  test ".perform_now should mark token as inactive when validation fails" do
    stub_failed_freefeed_response

    assert access_token.pending?

    perform_validation

    access_token.reload
    assert access_token.inactive?
  end

  test ".perform_now should raise and not disable token on transient HTTP error" do
    stub_app_token_info
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .to_raise(StandardError.new("Connection failed"))

    assert access_token.pending?

    assert_raises(StandardError) do
      perform_validation
    end

    access_token.reload
    assert access_token.validating?
  end

  test ".perform_now should raise and not disable token when JSON parsing fails" do
    stub_app_token_info
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => /Bearer freefeed_token_/,
          "Accept" => "application/json"
        }
      )
      .to_return(status: 200, body: "invalid json", headers: { "Content-Type" => "application/json" })

    assert access_token.pending?

    assert_raises(FreefeedClient::Error) do
      perform_validation
    end

    access_token.reload
    assert access_token.validating?
  end

  test ".perform_now should validate token using the token's host" do
    # Create token with custom host
    custom_token = create(:access_token, user: user, host: "https://custom.freefeed.com")

    stub_request(:get, "https://custom.freefeed.com/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => /Bearer freefeed_token_/,
          "Accept" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: { users: { username: "testuser" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, "https://custom.freefeed.com/v4/managedGroups")
      .with(
        headers: {
          "Authorization" => /Bearer freefeed_token_/,
          "Accept" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: [].to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, "https://custom.freefeed.com/v2/app-tokens/current")
      .to_return(
        status: 200,
        body: { token: { id: "token-1", scopes: AccessToken::TOKEN_SCOPES } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    perform_validation(custom_token)

    custom_token.reload
    assert custom_token.active?
  end

  test ".perform_now should broadcast status update on successful validation" do
    stub_successful_freefeed_response

    assert_nothing_raised do
      perform_validation
    end

    access_token.reload
    assert access_token.active?
  end

  test ".perform_now should broadcast status update on failed validation" do
    stub_failed_freefeed_response

    assert_nothing_raised do
      perform_validation
    end

    access_token.reload
    assert access_token.inactive?
  end

  test ".perform_now should raise and not disable token when response format is invalid" do
    stub_app_token_info
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => /Bearer freefeed_token_/,
          "Accept" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: { users: { screenName: "testuser", id: "test-id" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert access_token.pending?

    assert_raises(FreefeedClient::Error) do
      perform_validation
    end

    access_token.reload
    assert access_token.validating?
  end

  test ".perform_now should raise and not disable token on timeout" do
    stub_app_token_info
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .to_timeout

    assert access_token.pending?

    assert_raises(StandardError) do
      perform_validation
    end

    access_token.reload
    assert access_token.validating?
  end

  test ".perform_later should enqueue asynchronously" do
    stub_successful_freefeed_response
    run_id = start_validation

    assert_enqueued_with(job: TokenValidationJob, args: [access_token, run_id]) do
      TokenValidationJob.perform_later(access_token, run_id)
    end
  end

  test "#perform should ignore a superseded run before calling FreeFeed" do
    current_run_id = SecureRandom.uuid
    access_token.update!(status: :validating, validation_started_at: Time.current,
                        validation_run_id: current_run_id)

    TokenValidationJob.perform_now(access_token, SecureRandom.uuid)

    assert_not_requested :get, %r{#{Regexp.escape(access_token.host)}}
    assert_equal current_run_id, access_token.reload.validation_run_id
    assert access_token.validating?
  end

  test "#perform should not revive a run after its timeout" do
    run_id = SecureRandom.uuid
    access_token.update!(status: :validating, validation_started_at: 15.minutes.ago,
                        validation_run_id: run_id)
    AccessTokenValidationTimeoutJob.perform_now(access_token, run_id)

    TokenValidationJob.perform_now(access_token, run_id)

    assert_not_requested :get, %r{#{Regexp.escape(access_token.host)}}
    assert access_token.reload.inactive?
    assert_nil access_token.validation_run_id
  end

  test ".perform_now should succeed on retry after transient failure" do
    stub_app_token_info
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .to_timeout.times(1)
      .then.to_return(
        status: 200,
        body: {
          users: {
            username: "testuser",
            screenName: "Test User",
            id: "test-id"
          }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .with(
        headers: {
          "Authorization" => /Bearer freefeed_token_/,
          "Accept" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: [].to_json,
        headers: { "Content-Type" => "application/json" }
      )

    run_id = start_validation

    # First run raises — token stays validating
    assert_raises(StandardError) do
      TokenValidationJob.perform_now(access_token, run_id)
    end
    access_token.reload
    assert access_token.validating?
    # Second run (retry) succeeds
    TokenValidationJob.perform_now(access_token, run_id)
    access_token.reload
    assert access_token.active?
    assert_equal "testuser", access_token.owner
  end

  private

  def stub_successful_freefeed_response
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => /Bearer freefeed_token_/,
          "Accept" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: {
          users: {
            username: "testuser",
            screenName: "Test User",
            id: "test-id"
          }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .with(
        headers: {
          "Authorization" => /Bearer freefeed_token_/,
          "Accept" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: [].to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, "#{access_token.host}/v2/app-tokens/current")
      .to_return(
        status: 200,
        body: { token: { id: "token-1", scopes: AccessToken::TOKEN_SCOPES } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_app_token_info(scopes: AccessToken::TOKEN_SCOPES)
    stub_request(:get, "#{access_token.host}/v2/app-tokens/current")
      .to_return(
        status: 200,
        body: { token: { id: "token-1", scopes: scopes } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_failed_freefeed_response
    stub_app_token_info
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => /Bearer freefeed_token_/,
          "Accept" => "application/json"
        }
      )
      .to_return(
        status: 401,
        body: { err: "inactive or expired token" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end
end
