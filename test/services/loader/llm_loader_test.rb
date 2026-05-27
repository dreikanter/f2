require "test_helper"

class Loader::LlmLoaderTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def credential
    @credential ||= create(:llm_credential, :active, user: user)
  end

  def feed
    @feed ||= create(:feed,
                     user: user,
                     llm_credential: credential,
                     feed_profile_key: "llm_website_extractor",
                     params: { "url" => "https://example.com" })
  end

  def fake_client(payload)
    Class.new do
      def initialize(payload) = (@payload = payload)
      def call(_ctx, **_opts)
        LlmClient::Result.new(payload: @payload, usage_id: 42)
      end
    end.new(payload)
  end

  test "#load should return the items array from the LLM response" do
    items = [
      { "title" => "Post A", "uid" => "https://example.com/a" },
      { "title" => "Post B", "uid" => "https://example.com/b" }
    ]
    loader = Loader::LlmLoader.new(feed, llm_client: fake_client({ "items" => items }))

    assert_equal items, loader.load
  end

  test "#load should respect the limit option" do
    items = (1..10).map { |i| { "title" => "Post #{i}", "uid" => "https://example.com/#{i}" } }
    loader = Loader::LlmLoader.new(feed, llm_client: fake_client({ "items" => items }), limit: 3)

    assert_equal 3, loader.load.size
  end

  test "#load should raise when the payload is missing the items key" do
    loader = Loader::LlmLoader.new(feed, llm_client: fake_client({ "wrong" => "shape" }))

    error = assert_raises(StandardError) { loader.load }
    assert_match(/items/, error.message)
  end

  test "#rendered_prompt should substitute the source input" do
    feed = build(:feed, feed_profile_key: "llm_web_search", params: { "query" => "rust async" })
    loader = Loader::LlmLoader.new(feed)
    loader.stub(:config, { prompt_template: "Find {{input}}" }) do
      assert_equal "Find rust async", loader.send(:rendered_prompt)
    end
  end

  test "#rendered_prompt should treat user input literally (no regex backref expansion)" do
    feed = build(:feed, feed_profile_key: "llm_web_search", params: { "query" => 'a\0b' })
    loader = Loader::LlmLoader.new(feed)
    loader.stub(:config, { prompt_template: "Q: {{input}}" }) do
      assert_equal 'Q: a\0b', loader.send(:rendered_prompt)
    end
  end
end
