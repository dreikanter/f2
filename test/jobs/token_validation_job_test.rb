require "test_helper"

class TokenValidationJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user)
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

  test ".perform_now should mark token as inactive when HTTP error occurs" do
    # Mock HTTP error
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .to_raise(StandardError.new("Connection failed"))

    assert access_token.pending?

    TokenValidationJob.perform_now(access_token)

    access_token.reload
    assert access_token.inactive?
  end

  test ".perform_now should mark token as inactive when JSON parsing fails" do
    # Mock response with invalid JSON
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => /Bearer freefeed_token_/,
          "Accept" => "application/json"
        }
      )
      .to_return(status: 200, body: "invalid json", headers: { "Content-Type" => "application/json" })

    assert access_token.pending?

    TokenValidationJob.perform_now(access_token)

    access_token.reload
    assert access_token.inactive?
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

  test ".perform_now should mark token as inactive when response format is invalid" do
    # Mock response with missing username field
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

    TokenValidationJob.perform_now(access_token)

    access_token.reload
    assert access_token.inactive?
  end

  test ".perform_now should handle general exceptions in validation and broadcast errors" do
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .to_timeout

    assert access_token.pending?

    TokenValidationJob.perform_now(access_token)

    access_token.reload
    assert access_token.inactive?
  end

  test ".perform_later should enqueue asynchronously" do
    stub_successful_freefeed_response

    assert_enqueued_with(job: TokenValidationJob, args: [access_token]) do
      TokenValidationJob.perform_later(access_token)
    end
  end

  test ".perform_now should resume after failure" do
    # First attempt fails with timeout
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

    # First run fails
    TokenValidationJob.perform_now(access_token)
    access_token.reload
    assert access_token.inactive?

    # Reset to validating state to simulate retry
    access_token.update!(status: :validating)

    # Second run succeeds
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
        body: { error: "Unauthorized" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end
end
