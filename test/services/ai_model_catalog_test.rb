require "test_helper"

class AiModelCatalogTest < ActiveSupport::TestCase
  include OpenaiModelsTestHelpers

  def credential
    @credential ||= build(:ai_credential, provider: "openai", credential_data: { "api_key" => "first-key" })
  end

  test "#fetch should list models with advisory SDK metadata and preserve unknown IDs" do
    request = stub_openai_models(key: "first-key")

    credential.available_models = AiModelCatalog.fetch(credential)

    assert_equal %w[gpt-5.6-luna future-openai-model text-embedding-3-small], credential.available_models.pluck("id")
    assert_equal %w[gpt-5.6-luna future-openai-model], credential.supported_models.pluck("id")
    assert_equal "GPT-5.6 Luna", credential.available_models.first["name"]
    assert_equal 1_050_000, credential.model_metadata("gpt-5.6-luna")["context_window"]
    assert_equal({}, credential.model_metadata("future-openai-model"))
    assert_requested request, times: 1
    assert_not_requested :post, /./
  end

  test "#fetch should keep two keys and their catalogs isolated" do
    first = stub_openai_models(key: "first-key")
    second = stub_openai_models(key: "second-key", fixture: "empty")
    other = build(:ai_credential, provider: "openai", credential_data: { "api_key" => "second-key" })
    original_key = RubyLLM.config.openai_api_key

    assert_not_empty AiModelCatalog.fetch(credential)
    assert_empty AiModelCatalog.fetch(other)
    assert_equal original_key, RubyLLM.config.openai_api_key
    assert_requested first, times: 1
    assert_requested second, times: 1
  end

  test "#fetch should reject a malformed list without accepting its valid prefix" do
    stub_openai_models(key: "first-key", fixture: "malformed")

    error = assert_raises(AiModelCatalog::Error) { AiModelCatalog.fetch(credential) }

    assert_equal :malformed, error.category
    assert_not error.invalid_key?
  end

  test "#fetch should sanitize invalid JSON including its exception cause" do
    stub_request(:get, "https://api.openai.com/v1/models").to_return(body: "sk-sample-secret")

    error = assert_raises(AiModelCatalog::Error) { AiModelCatalog.fetch(credential) }

    assert_equal :malformed, error.category
    assert_not_includes error.full_message, "sk-sample-secret"
    assert_nil error.cause
  end

  test "#fetch should classify only an explicitly rejected key as invalid" do
    stub_openai_models(key: "first-key", fixture: "invalid_key", status: 401)

    error = assert_raises(AiModelCatalog::Error) { AiModelCatalog.fetch(credential) }

    assert error.invalid_key?
    assert_equal 401, error.status
    assert_not_includes error.full_message, "sk-sample-secret"
  end

  test "#fetch should preserve IP restrictions as permission errors" do
    stub_openai_models(key: "first-key", fixture: "ip_restriction", status: 401)

    error = assert_raises(AiModelCatalog::Error) { AiModelCatalog.fetch(credential) }

    assert_equal :permission, error.category
    assert_not error.invalid_key?
  end

  test "#fetch should preserve access restrictions as permission errors" do
    stub_openai_models(key: "first-key", fixture: "permission", status: 403)

    error = assert_raises(AiModelCatalog::Error) { AiModelCatalog.fetch(credential) }

    assert_equal :permission, error.category
    assert_not error.invalid_key?
  end

  test "#fetch should classify quota exhaustion without invalidating the key" do
    stub_openai_models(key: "first-key", fixture: "quota", status: 429)

    error = assert_raises(AiModelCatalog::Error) { AiModelCatalog.fetch(credential) }

    assert_equal :rate_limit, error.category
    assert_not error.invalid_key?
  end

  test "#fetch should handle an HTTP failure without a JSON error body" do
    stub_request(:get, "https://api.openai.com/v1/models").to_return(status: 502, body: "Bad gateway")

    error = assert_raises(AiModelCatalog::Error) { AiModelCatalog.fetch(credential) }

    assert_equal :provider, error.category
    assert_equal 502, error.status
  end

  test "#fetch should sanitize transport failures" do
    stub_request(:get, "https://api.openai.com/v1/models").to_timeout

    error = assert_raises(AiModelCatalog::Error) { AiModelCatalog.fetch(credential) }

    assert_equal :connection, error.category
    assert_nil error.cause
  end

  test "#fetch should refuse redirects without forwarding the credential" do
    stub_request(:get, "https://api.openai.com/v1/models")
      .to_return(status: 302, headers: { "Location" => "https://example.com/models" })

    assert_raises(AiModelCatalog::Error) { AiModelCatalog.fetch(credential) }
    assert_not_requested :get, "https://example.com/models"
  end

  test "#fetch should keep unsupported providers unavailable without HTTP" do
    credential.provider = "moonshot"

    assert_raises(AiModelCatalog::Unavailable) { AiModelCatalog.fetch(credential) }
    assert_not_requested :any, /./
  end
end
