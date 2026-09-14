require "test_helper"

class LlmProvider::OpenaiTest < ActiveSupport::TestCase
  include OpenaiModelsTestHelpers

  def client
    @client ||= LlmProvider::Openai.new(credential_data: { "api_key" => "first-key" })
  end

  test "#validate_credentials! should classify only an explicitly rejected key as invalid" do
    stub_openai_models(key: "first-key", fixture: "invalid_key", status: 401)

    error = assert_raises(LlmProvider::Error) { client.validate_credentials! }

    assert error.invalid_key?
    assert_equal 401, error.status
    assert_not_includes error.full_message, "sk-sample-secret"
  end

  test "#validate_credentials! should preserve IP restrictions as permission errors" do
    stub_openai_models(key: "first-key", fixture: "ip_restriction", status: 401)

    error = assert_raises(LlmProvider::Error) { client.validate_credentials! }

    assert_equal :permission, error.category
    assert_not error.invalid_key?
  end

  test "#validate_credentials! should preserve access restrictions as permission errors" do
    stub_openai_models(key: "first-key", fixture: "permission", status: 403)

    error = assert_raises(LlmProvider::Error) { client.validate_credentials! }

    assert_equal :permission, error.category
    assert_not error.invalid_key?
  end

  test "#validate_credentials! should classify quota exhaustion without invalidating the key" do
    stub_openai_models(key: "first-key", fixture: "quota", status: 429)

    error = assert_raises(LlmProvider::Error) { client.validate_credentials! }

    assert_equal :rate_limit, error.category
    assert_not error.invalid_key?
  end

  test "#validate_credentials! should handle an HTTP failure without a JSON error body" do
    stub_request(:get, "https://api.openai.com/v1/models").to_return(status: 502, body: "Bad gateway")

    error = assert_raises(LlmProvider::Error) { client.validate_credentials! }

    assert_equal :provider, error.category
    assert_equal 502, error.status
  end

  test "#validate_credentials! should sanitize transport failures" do
    stub_request(:get, "https://api.openai.com/v1/models").to_timeout

    error = assert_raises(LlmProvider::Error) { client.validate_credentials! }

    assert_equal :connection, error.category
    assert_nil error.cause
  end

  test "#validate_credentials! should refuse redirects without forwarding the credential" do
    stub_request(:get, "https://api.openai.com/v1/models")
      .to_return(status: 302, headers: { "Location" => "https://example.com/models" })

    assert_raises(LlmProvider::Error) { client.validate_credentials! }
    assert_not_requested :get, "https://example.com/models"
  end
end
