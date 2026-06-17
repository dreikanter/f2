require "test_helper"

class LlmClientTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def credential
    @credential ||= create(:ai_credential, :active, user: user)
  end

  def feed
    @feed ||= create(:feed,
                     user: user,
                     ai_credential: credential,
                     feed_profile_key: "rss",
                     params: { "url" => "http://example.com/feed.xml" })
  end

  def successful_response
    LlmClient::ProviderResponse.new(
      payload: { "items" => [{ "title" => "Post 1" }] },
      input_tokens: 100_000,
      output_tokens: 5_000,
      cache_write_tokens: 0,
      cache_read_tokens: 0
    )
  end

  def stub_provider_response(client, response = successful_response)
    client.define_singleton_method(:invoke_provider) { |**_| response }
  end

  def stub_provider_to_raise(client, error)
    client.define_singleton_method(:invoke_provider) { |**_| raise error }
  end

  def stub_provider_models(client, &block)
    client.define_singleton_method(:fetch_provider_models, &block)
  end

  def default_ctx(**overrides)
    LlmClient::CallContext.new(
      feed: feed,
      profile_key: "llm_website_extractor",
      stage: :loader,
      model: "claude-sonnet-4-6",
      **overrides
    )
  end

  def call_opts
    {
      prompt: "Extract posts",
      output_schema: {
        "type" => "object",
        "properties" => { "items" => { "type" => "array" } },
        "required" => ["items"]
      }
    }
  end

  test ".for should resolve a feed to its assigned credential" do
    client = LlmClient.for(feed)
    assert_equal credential, client.credential
  end

  test ".for should resolve a user+provider to the active default credential" do
    create(:ai_credential, :active, user: user)
    default = create(:ai_credential, :active, :default, user: user)

    client = LlmClient.for(user, "anthropic")

    assert_equal default, client.credential
  end

  test ".for should raise CredentialMissing when no active credential exists" do
    create(:ai_credential, :inactive, user: user)

    assert_raises(LlmClient::CredentialMissing) do
      LlmClient.for(user, "anthropic")
    end
  end

  test ".for should accept an explicit credential" do
    client = LlmClient.for(credential)
    assert_equal credential, client.credential
  end

  test "#call should raise DetectionForbidden when the detection-phase flag is set" do
    client = LlmClient.new(credential)
    stub_provider_response(client)

    Thread.current[:llm_detection_phase] = true
    assert_raises(LlmClient::DetectionForbidden) { client.call(default_ctx, **call_opts) }
  ensure
    Thread.current[:llm_detection_phase] = false
  end

  test "#call should write an LlmUsage row on success and return a Result" do
    client = LlmClient.new(credential)
    stub_provider_response(client)

    assert_difference("LlmUsage.count", 1) do
      result = client.call(default_ctx, **call_opts)

      assert_kind_of LlmClient::Result, result
      assert_equal({ "items" => [{ "title" => "Post 1" }] }, result.payload)
      assert_kind_of Integer, result.usage_id
    end

    usage = LlmUsage.last
    assert_equal "success", usage.outcome
    assert_equal "loader", usage.stage
    assert_equal "anthropic", usage.provider
    assert_equal "claude-sonnet-4-6", usage.model
    assert_equal 100_000, usage.input_tokens
    assert_equal 5_000, usage.output_tokens
    assert usage.cost_estimate_cents.positive?, "expected non-zero cost for a known model"
    assert_kind_of Integer, usage.duration_ms
    assert usage.duration_ms >= 0
    assert_nil usage.error_message
  end

  test "#call should populate error_message on provider error" do
    client = LlmClient.new(credential)
    stub_provider_to_raise(client, RubyLLM::ServerError.new("downstream failure"))

    assert_raises(LlmClient::ProviderError) { client.call(default_ctx, **call_opts) }

    usage = LlmUsage.last
    assert_equal "provider_error", usage.outcome
    assert_not_nil usage.error_message
    assert_includes usage.error_message, "downstream failure"
  end

  test "#call should populate error_message and duration_ms on schema error" do
    client = LlmClient.new(credential)
    bad_response = LlmClient::ProviderResponse.new(
      payload: { "wrong" => "shape" },
      input_tokens: 10, output_tokens: 5,
      cache_write_tokens: 0, cache_read_tokens: 0
    )
    stub_provider_response(client, bad_response)

    assert_raises(LlmClient::SchemaError) { client.call(default_ctx, **call_opts) }

    usage = LlmUsage.last
    assert_equal "schema_error", usage.outcome
    assert_not_nil usage.error_message
    assert_not_nil usage.duration_ms
    assert_equal 10, usage.input_tokens
    assert_equal 5, usage.output_tokens
  end

  test "#call should populate error_message on rate limit" do
    client = LlmClient.new(credential)
    stub_provider_to_raise(client, RubyLLM::RateLimitError.new("rate limit exceeded"))

    assert_raises(LlmClient::RateLimited) { client.call(default_ctx, **call_opts) }

    usage = LlmUsage.last
    assert_equal "rate_limited", usage.outcome
    assert_not_nil usage.error_message
    assert_not_nil usage.duration_ms
  end

  test "#call should populate error_message and duration_ms on timeout" do
    client = LlmClient.new(credential)
    stub_provider_to_raise(client, Net::ReadTimeout.new)

    assert_raises(LlmClient::Timeout) { client.call(default_ctx, **call_opts) }

    usage = LlmUsage.last
    assert_equal "timeout", usage.outcome
    assert_not_nil usage.error_message
    assert_not_nil usage.duration_ms
  end

  test "#call should raise SchemaError and record a failed usage row when the response violates the schema" do
    client = LlmClient.new(credential)
    bad_response = LlmClient::ProviderResponse.new(
      payload: { "wrong" => "shape" },
      input_tokens: 10, output_tokens: 5,
      cache_write_tokens: 0, cache_read_tokens: 0
    )
    stub_provider_response(client, bad_response)

    assert_difference("LlmUsage.count", 1) do
      assert_raises(LlmClient::SchemaError) { client.call(default_ctx, **call_opts) }
    end

    assert_equal "schema_error", LlmUsage.last.outcome
  end

  test "#call should raise RateLimited and record a usage row on RubyLLM::RateLimitError" do
    client = LlmClient.new(credential)
    stub_provider_to_raise(client, RubyLLM::RateLimitError.new("429"))

    assert_difference("LlmUsage.count", 1) do
      assert_raises(LlmClient::RateLimited) { client.call(default_ctx, **call_opts) }
    end

    assert_equal "rate_limited", LlmUsage.last.outcome
  end

  test "#call should raise ProviderError on generic RubyLLM::Error and record the failure" do
    client = LlmClient.new(credential)
    stub_provider_to_raise(client, RubyLLM::ServerError.new("500"))

    assert_difference("LlmUsage.count", 1) do
      assert_raises(LlmClient::ProviderError) { client.call(default_ctx, **call_opts) }
    end

    assert_equal "provider_error", LlmUsage.last.outcome
  end

  test "#call should raise Timeout and record a usage row on Net::ReadTimeout" do
    client = LlmClient.new(credential)
    stub_provider_to_raise(client, Net::ReadTimeout.new)

    assert_difference("LlmUsage.count", 1) do
      assert_raises(LlmClient::Timeout) { client.call(default_ctx, **call_opts) }
    end

    assert_equal "timeout", LlmUsage.last.outcome
  end

  test "#call should accept feed:nil for previews and skip the feed reference on the usage row" do
    client = LlmClient.new(credential)
    stub_provider_response(client)

    client.call(default_ctx(feed: nil, purpose: :preview), **call_opts)

    usage = LlmUsage.last
    assert_nil usage.feed_id
    assert_equal "preview", usage.purpose
  end

  test "#health_check should return true when provider models are accessible" do
    client = LlmClient.new(credential)
    stub_provider_models(client) { [] }

    assert_equal true, client.health_check
    assert_equal 0, LlmUsage.count
  end

  test "#health_check should raise AuthError when the provider rejects the key" do
    client = LlmClient.new(credential)
    stub_provider_models(client) { raise RubyLLM::UnauthorizedError, "invalid key" }

    assert_raises(LlmClient::AuthError) { client.health_check }
    assert_equal 0, LlmUsage.count
  end

  test "#health_check should raise ProviderError on other provider failures" do
    client = LlmClient.new(credential)
    stub_provider_models(client) { raise RubyLLM::ServerError, "upstream error" }

    assert_raises(LlmClient::ProviderError) { client.health_check }
  end

  test "#health_check should call the provider models endpoint with the credential api_key" do
    client = LlmClient.new(credential)

    fake_provider_class = Class.new do
      def initialize(_config); end
      def list_models; []; end
    end

    RubyLLM::Provider.stub(:resolve, fake_provider_class) do
      assert_equal true, client.health_check
      assert_equal 0, LlmUsage.count
    end
  end

  test "#call should raise AuthError for RubyLLM::UnauthorizedError" do
    client = LlmClient.new(credential)
    stub_provider_to_raise(client, RubyLLM::UnauthorizedError.new("401"))

    assert_raises(LlmClient::AuthError) { client.call(default_ctx, **call_opts) }
    assert_equal "provider_error", LlmUsage.last.outcome
  end

  test "#call should raise AuthError for RubyLLM::ForbiddenError" do
    client = LlmClient.new(credential)
    stub_provider_to_raise(client, RubyLLM::ForbiddenError.new("403"))

    assert_raises(LlmClient::AuthError) { client.call(default_ctx, **call_opts) }
  end

  test "#call should raise AuthError for RubyLLM::PaymentRequiredError" do
    client = LlmClient.new(credential)
    stub_provider_to_raise(client, RubyLLM::PaymentRequiredError.new("402"))

    assert_raises(LlmClient::AuthError) { client.call(default_ctx, **call_opts) }
  end

  test "#call should map RubyLLM::ModelNotFoundError to ProviderError" do
    client = LlmClient.new(credential)
    stub_provider_to_raise(client, RubyLLM::ModelNotFoundError.new("unknown model"))

    assert_difference("LlmUsage.count", 1) do
      assert_raises(LlmClient::ProviderError) { client.call(default_ctx, **call_opts) }
    end

    assert_equal "provider_error", LlmUsage.last.outcome
  end

  test "#call should map RubyLLM::ConfigurationError to ProviderError" do
    client = LlmClient.new(credential)
    stub_provider_to_raise(client, RubyLLM::ConfigurationError.new("misconfigured"))

    assert_raises(LlmClient::ProviderError) { client.call(default_ctx, **call_opts) }
    assert_equal "provider_error", LlmUsage.last.outcome
  end
end
