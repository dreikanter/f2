require "test_helper"

class AiCredentialValidator::XaiTest < ActiveSupport::TestCase
  test "#errors should require a nonblank string API key" do
    assert_empty AiCredentialValidator::Xai.new(credential_data: { "api_key" => "test-key" }).errors
    assert_equal ["Enter your API key"], AiCredentialValidator::Xai.new(credential_data: nil).errors
    assert_equal ["Enter your API key"], AiCredentialValidator::Xai.new(credential_data: { "api_key" => " " }).errors
    assert_equal ["Enter your API key"], AiCredentialValidator::Xai.new(credential_data: { "api_key" => 123 }).errors
  end

  test "#validate! should authenticate the credential through the account endpoint" do
    credential = build(:ai_credential, provider: "xai", credential_data: { "api_key" => "xai-test-key" })
    request = stub_request(:get, "https://api.x.ai/v1/api-key")
      .with(headers: { "Authorization" => "Bearer xai-test-key", "Accept" => "application/json" })
      .to_return_json(body: key_status)

    assert credential.valid?
    assert credential.validate_credentials!
    assert_requested request, times: 1
    assert_not_requested :post, /./
  end

  test "#validate! should reject invalid authentication without exposing the response body" do
    stub_request(:get, "https://api.x.ai/v1/api-key").to_return(status: 401, body: "secret key in response")

    error = assert_raises(AiCredentialValidator::Error) { validator.validate! }

    assert error.invalid_key?
    assert_equal 401, error.status
    assert_not_includes error.full_message, "secret key"
  end

  test "#validate! should preserve access restrictions as permission errors" do
    stub_request(:get, "https://api.x.ai/v1/api-key").to_return(status: 403)

    error = assert_raises(AiCredentialValidator::Error) { validator.validate! }

    assert_equal :permission, error.category
    assert_not error.invalid_key?
  end

  test "#validate! should reject a disabled key" do
    stub_request(:get, "https://api.x.ai/v1/api-key").to_return_json(body: key_status.merge(api_key_disabled: true))

    error = assert_raises(AiCredentialValidator::Error) { validator.validate! }

    assert_equal :permission, error.category
  end

  test "#validate! should reject a blocked key" do
    stub_request(:get, "https://api.x.ai/v1/api-key").to_return_json(body: key_status.merge(api_key_blocked: true))

    error = assert_raises(AiCredentialValidator::Error) { validator.validate! }

    assert_equal :permission, error.category
  end

  test "#validate! should reject a blocked team" do
    stub_request(:get, "https://api.x.ai/v1/api-key").to_return_json(body: key_status.merge(team_blocked: true))

    error = assert_raises(AiCredentialValidator::Error) { validator.validate! }

    assert_equal :permission, error.category
  end

  test "#validate! should preserve rate limiting without invalidating the key" do
    stub_request(:get, "https://api.x.ai/v1/api-key").to_return(status: 429)

    error = assert_raises(AiCredentialValidator::Error) { validator.validate! }

    assert_equal :rate_limit, error.category
    assert_not error.invalid_key?
  end

  test "#validate! should handle provider failure without a JSON body" do
    stub_request(:get, "https://api.x.ai/v1/api-key").to_return(status: 502, body: "Bad gateway")

    error = assert_raises(AiCredentialValidator::Error) { validator.validate! }

    assert_equal :provider, error.category
    assert_equal 502, error.status
  end

  test "#validate! should reject incomplete key status" do
    stub_request(:get, "https://api.x.ai/v1/api-key").to_return_json(body: { api_key_id: "test-key-id" })

    error = assert_raises(AiCredentialValidator::Error) { validator.validate! }

    assert_equal :provider, error.category
  end

  test "#validate! should sanitize malformed key status" do
    stub_request(:get, "https://api.x.ai/v1/api-key").to_return(body: "secret in malformed JSON")

    error = assert_raises(AiCredentialValidator::Error) { validator.validate! }

    assert_equal :provider, error.category
    assert_nil error.cause
    assert_not_includes error.full_message, "secret"
  end

  test "#validate! should sanitize transport failures" do
    stub_request(:get, "https://api.x.ai/v1/api-key").to_timeout

    error = assert_raises(AiCredentialValidator::Error) { validator.validate! }

    assert_equal :connection, error.category
    assert_nil error.cause
  end

  test "#validate! should refuse redirects without forwarding the credential" do
    stub_request(:get, "https://api.x.ai/v1/api-key")
      .to_return(status: 302, headers: { "Location" => "https://example.com/api-key" })

    assert_raises(AiCredentialValidator::Error) { validator.validate! }
    assert_not_requested :get, "https://example.com/api-key"
  end

  private

  def validator
    AiCredentialValidator::Xai.new(credential_data: { "api_key" => "xai-test-key" })
  end

  def key_status
    { api_key_id: "test-key-id", api_key_blocked: false, api_key_disabled: false, team_blocked: false }
  end
end
