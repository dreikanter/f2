require "test_helper"

class Loader::LlmLoaderTest < ActiveSupport::TestCase
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
                     feed_profile_key: "llm",
                     params: { "prompt" => "https://example.com" })
  end

  def openrouter_credential
    @openrouter_credential ||= create(:ai_credential, :active, user: user, provider: "openrouter")
  end

  # Two-step provider feed, for exercising the gather→structure path.
  def openrouter_feed
    @openrouter_feed ||= create(:feed,
                                user: user,
                                ai_credential: openrouter_credential,
                                feed_profile_key: "llm",
                                params: { "prompt" => "https://example.com" })
  end

  # Fake client: a call carrying a schema returns the structured items, a
  # schema-less (gather) call returns raw text. Works for both the combined
  # one-call path and the two-call path. Records each call's opts + model.
  def fake_client(structured:, gathered: "raw gathered text", credential: self.credential)
    Class.new do
      attr_reader :credential, :calls

      def initialize(structured, gathered, credential)
        @structured = structured
        @gathered = gathered
        @credential = credential
        @calls = []
      end

      def call(ctx, **opts)
        @calls << opts.merge(model: ctx.model)
        payload = opts[:output_schema] ? @structured : @gathered
        LlmClient::Result.new(payload: payload, usage_id: @calls.size)
      end
    end.new(structured, gathered, credential)
  end

  test "#load should return the items array from the structured response" do
    items = [
      { "title" => "Post A", "source_url" => "https://example.com/a" },
      { "title" => "Post B", "source_url" => "https://example.com/b" }
    ]
    loader = Loader::LlmLoader.new(feed, llm_client: fake_client(structured: { "items" => items }))

    assert_equal items, loader.load
  end

  test "#load should use one combined web+schema call for a combined-extraction provider" do
    client = fake_client(structured: { "items" => [] })
    Loader::LlmLoader.new(feed, llm_client: client).load

    assert_equal 1, client.calls.size
    assert_equal true, client.calls[0][:web]
    assert client.calls[0][:output_schema].present?
  end

  test "#load should gather then structure for a two-step provider" do
    client = fake_client(structured: { "items" => [] }, credential: openrouter_credential)
    Loader::LlmLoader.new(openrouter_feed, llm_client: client).load

    assert_equal 2, client.calls.size
    assert_equal true, client.calls[0][:web]
    assert_nil client.calls[0][:output_schema]
    assert_equal false, client.calls[1][:web]
    assert client.calls[1][:output_schema].present?
  end

  test "#load should feed the gathered content into the structuring prompt (two-step)" do
    client = fake_client(structured: { "items" => [] }, gathered: "GATHERED-XYZ", credential: openrouter_credential)
    Loader::LlmLoader.new(openrouter_feed, llm_client: client).load

    assert_match "GATHERED-XYZ", client.calls[1][:prompt]
  end

  test "#load should respect the limit option" do
    items = (1..10).map { |i| { "title" => "Post #{i}", "source_url" => "https://example.com/#{i}" } }
    loader = Loader::LlmLoader.new(feed, llm_client: fake_client(structured: { "items" => items }), limit: 3)

    assert_equal 3, loader.load.size
  end

  test "#load should raise when the structured payload is missing the items key" do
    loader = Loader::LlmLoader.new(feed, llm_client: fake_client(structured: { "wrong" => "shape" }))

    error = assert_raises(StandardError) { loader.load }
    assert_match(/items/, error.message)
  end

  test "#load should use the feed's chosen model when the credential still supports it" do
    supported = create(:ai_credential, :active, user: user, available_models: [{ "id" => "claude-sonnet-4-6" }])
    supported_feed = create(:feed, user: user, ai_credential: supported, feed_profile_key: "llm",
                                   params: { "prompt" => "x" }, ai_model: "claude-sonnet-4-6")
    client = fake_client(structured: { "items" => [] }, credential: supported)
    Loader::LlmLoader.new(supported_feed, llm_client: client).load

    assert_equal ["claude-sonnet-4-6"], client.calls.map { |c| c[:model] }
  end

  test "#load should fall back to a supported model and record a notice when the chosen model dropped" do
    supported = create(:ai_credential, :active, user: user, available_models: [{ "id" => "claude-sonnet-4-6" }])
    dropped_feed = create(:feed, user: user, ai_credential: supported, feed_profile_key: "llm",
                                 params: { "prompt" => "x" }, ai_model: "removed-model")
    client = fake_client(structured: { "items" => [] }, credential: supported)

    assert_difference -> { dropped_feed.events.where(type: "feed_ai_model_unavailable").count }, 1 do
      Loader::LlmLoader.new(dropped_feed, llm_client: client).load
    end

    assert_equal ["claude-sonnet-4-6"], client.calls.map { |c| c[:model] }
  end

  test "#load should record a notice and use the provider default when the whole snapshot dropped" do
    empty = create(:ai_credential, :active, user: user, available_models: [])
    orphaned = create(:feed, user: user, ai_credential: empty, feed_profile_key: "llm",
                             params: { "prompt" => "x" }, ai_model: "claude-opus-4-7")
    client = fake_client(structured: { "items" => [] }, credential: empty)

    assert_difference -> { orphaned.events.where(type: "feed_ai_model_unavailable").count }, 1 do
      Loader::LlmLoader.new(orphaned, llm_client: client).load
    end

    assert_equal [LlmProvider.find("anthropic").default_model], client.calls.map { |c| c[:model] }
  end

  test "#load should fall back to the provider default model when no override" do
    assert_nil feed.ai_model
    client = fake_client(structured: { "items" => [] }, credential: credential)
    Loader::LlmLoader.new(feed, llm_client: client).load

    assert_equal LlmProvider.find(credential.provider).default_model, client.calls.first[:model]
  end

  test "#rendered_prompt should substitute the source input" do
    feed = build(:feed, feed_profile_key: "llm", params: { "prompt" => "rust async" })
    loader = Loader::LlmLoader.new(feed)
    loader.stub(:config, { prompt_template: "Find {{input}}" }) do
      assert_equal "Find rust async", loader.send(:rendered_prompt)
    end
  end

  test "#rendered_prompt should treat user input literally (no regex backref expansion)" do
    feed = build(:feed, feed_profile_key: "llm", params: { "prompt" => 'a\0b' })
    loader = Loader::LlmLoader.new(feed)
    loader.stub(:config, { prompt_template: "Q: {{input}}" }) do
      assert_equal 'Q: a\0b', loader.send(:rendered_prompt)
    end
  end
end
