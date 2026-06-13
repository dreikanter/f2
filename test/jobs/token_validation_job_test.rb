require "test_helper"

class TokenValidationJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user)
  end

  test ".perform_now should reserve two GETs and reschedule when throttled" do
    captured = nil
    RateLimit.stub(:acquire, lambda { |_policy, subject:, cost:|
      captured = [subject, cost]
      RateLimit::Result.new(allowed: false, retry_after: 2)
    }) do
      assert_enqueued_with(job: TokenValidationJob) do
        TokenValidationJob.perform_now(access_token)
      end
    end

    assert_equal [access_token.rate_limit_subject, { get: 2 }], captured
  end

  test ".perform_now should reset token to pending when throttle retries are exhausted" do
    access_token.validating!

    job = TokenValidationJob.new(access_token)
    job.executions = RateLimited::MAX_ATTEMPTS

    RateLimit.stub(:acquire, ->(*, **) { RateLimit::Result.new(allowed: false, retry_after: 2) }) do
      Rails.error.stub(:report, ->(*, **) { }) do
        assert_no_enqueued_jobs { job.perform_now }
      end
    end

    access_token.reload
    assert access_token.pending?
  end

  test ".perform_now should reschedule without failing when validation is throttled mid-call" do
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .to_return(status: 429, headers: { "Retry-After" => "30" })

    reported = []
    assert_enqueued_with(job: TokenValidationJob) do
      Rails.error.stub(:report, ->(*args, **) { reported << args }) do
        TokenValidationJob.perform_now(access_token)
      end
    end

    assert_empty reported, "a handled throttle must not be reported as a fault"
    assert_not access_token.reload.inactive?, "a throttle must not disable the token"
  end

  test ".perform_now should mark token as active when validation succeeds" do
    stub_successful_freefeed_response

    assert access_token.pending?

    TokenValidationJob.perform_now(access_token)

    access_token.reload
    assert access_token.active?
    assert_equal "testuser", access_token.owner
  end

  test ".perform_now should mark token as inactive when validation fails" do
    stub_failed_freefeed_response

    assert access_token.pending?

    TokenValidationJob.perform_now(access_token)

    access_token.reload
    assert access_token.inactive?
  end

  test ".perform_now should raise and not disable token on transient HTTP error" do
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .to_raise(StandardError.new("Connection failed"))

    assert access_token.pending?

    assert_raises(StandardError) do
      TokenValidationJob.perform_now(access_token)
    end

    access_token.reload
    assert access_token.validating?
  end

  test ".perform_now should raise and not disable token when JSON parsing fails" do
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
      TokenValidationJob.perform_now(access_token)
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

    TokenValidationJob.perform_now(custom_token)

    custom_token.reload
    assert custom_token.active?
  end

  test ".perform_now should broadcast status update on successful validation" do
    stub_successful_freefeed_response

    assert_nothing_raised do
      TokenValidationJob.perform_now(access_token)
    end

    access_token.reload
    assert access_token.active?
  end

  test ".perform_now should broadcast status update on failed validation" do
    stub_failed_freefeed_response

    assert_nothing_raised do
      TokenValidationJob.perform_now(access_token)
    end

    access_token.reload
    assert access_token.inactive?
  end

  test ".perform_now should raise and not disable token when response format is invalid" do
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
      TokenValidationJob.perform_now(access_token)
    end

    access_token.reload
    assert access_token.validating?
  end

  test ".perform_now should raise and not disable token on timeout" do
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .to_timeout

    assert access_token.pending?

    assert_raises(StandardError) do
      TokenValidationJob.perform_now(access_token)
    end

    access_token.reload
    assert access_token.validating?
  end

  test ".perform_later should enqueue asynchronously" do
    stub_successful_freefeed_response

    assert_enqueued_with(job: TokenValidationJob, args: [access_token]) do
      TokenValidationJob.perform_later(access_token)
    end
  end

  test ".perform_now should succeed on retry after transient failure" do
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

    # First run raises — token stays validating
    assert_raises(StandardError) do
      TokenValidationJob.perform_now(access_token)
    end
    access_token.reload
    assert access_token.validating?

    # Second run (retry) succeeds
    TokenValidationJob.perform_now(access_token)
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
  end

  def stub_failed_freefeed_response
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
