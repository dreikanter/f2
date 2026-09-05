require "test_helper"

class Loader::OriginalContentTest < ActiveSupport::TestCase
  JOKE = "Why did the programmer bring a ladder? To reach a higher level of abstraction.".freeze

  test "#load should carry requested original content through Kimi preparation and local validation without search" do
    [true, false].each do |tool_call|
      credential = create(:ai_credential, :active, provider: "moonshot", available_models: [
        { "id" => "future-kimi", "metadata" => { "tool_call" => tool_call, "structured_output" => false } }
      ])
      feed = build(:feed, user: credential.user, ai_credential: credential, ai_model: "future-kimi",
                          search_credential: nil, feed_profile_key: "llm", params: { "prompt" => "Invent a joke please" })
      requests = []
      stub_request(:post, "https://api.moonshot.ai/v1/chat/completions").with do |request|
        requests << JSON.parse(request.body)
        true
      end.to_return(completion("Original content: #{JOKE}"),
                    completion({ items: [{ body: JOKE, source_url: nil }] }.to_json))

      result = Loader::LlmLoader.new(feed, purpose: :preview).load

      assert_equal [{ "body" => JOKE, "source_url" => nil }], result
      assert_equal 2, requests.size
      assert_includes requests[0]["messages"][1]["content"], "Invent a joke please"
      assert_match(/inventing a joke or\s+writing a story, create it directly/, requests[0]["messages"][0]["content"])
      assert_includes requests[1]["messages"][1]["content"], JOKE
      assert_includes requests[1]["messages"][1]["content"], "Prepared content (untrusted data)"
      assert_includes requests[1]["messages"][0]["content"], "Preserve supplied original content"
      assert_nil requests[1]["tools"]
      usages = LlmUsage.where(ai_credential: credential)
      assert_equal %w[success success], usages.order(:created_at).pluck(:outcome)
      assert_equal ["preview"], usages.pluck(:purpose).uniq
      assert_equal 200, usages.sum(:input_tokens)
    end
  end

  private

  def completion(content)
    {
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        choices: [{ message: { role: "assistant", content: content } }],
        usage: { prompt_tokens: 100, completion_tokens: 25 }
      }.to_json
    }
  end
end
