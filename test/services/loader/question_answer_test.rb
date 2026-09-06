require "test_helper"

class Loader::QuestionAnswerTest < ActiveSupport::TestCase
  PROMPT = "Is the AGI achieved yet? Strict requirement: Short answer only, yes or no. " \
           "If yes, add a link. If not sure, also add a link, and very short summary, strictly under 80 characters.".freeze
  ENDPOINT = "https://api.moonshot.ai/v1/chat/completions".freeze
  FORMULA = "https://api.moonshot.ai/v1/formulas/moonshot/web-search:latest".freeze

  def credential
    @credential ||= create(:ai_credential, :active, provider: "moonshot", available_models: [
      { "id" => "future-kimi", "metadata" => { "structured_output" => false } }
    ])
  end

  def feed(prompt = PROMPT)
    build(:feed, user: credential.user, ai_credential: credential, ai_model: "future-kimi",
                 search_credential: nil, feed_profile_key: "llm", params: { "prompt" => prompt })
  end

  def completion(content)
    { headers: { "Content-Type" => "application/json" }, body: {
      choices: [{ message: { role: "assistant", content: content }, finish_reason: "stop" }],
      usage: { prompt_tokens: 100, completion_tokens: 25 }
    }.to_json }
  end

  def stub_answers(*answers)
    @requests = []
    stub_request(:get, "#{FORMULA}/tools").to_return(status: 404)
    stub_request(:post, ENDPOINT).with do |request|
      @requests << JSON.parse(request.body)
      true
    end.to_return(*answers.map { |answer| completion(answer) })
  end

  test "#load should retain short answers and uncertainty with the original question during structuring" do
    ["No", "Not sure. Evidence is inconclusive. https://example.com/evidence"].each do |answer|
      stub_answers(answer, { items: [{ body: answer, source_url: nil }] }.to_json)

      items = Loader::LlmLoader.new(feed, purpose: :preview).load

      assert_equal [{ "body" => answer, "source_url" => nil }], items
      assert_operator items.sole["body"].length, :<, 80
      assert_equal 2, @requests.size
      assert_includes @requests.first["messages"][1]["content"], PROMPT
      assert_includes @requests.last["messages"][1]["content"], PROMPT
      assert_includes @requests.last["messages"][1]["content"], answer
      assert_includes @requests.first["messages"][0]["content"], Loader::LlmPrompts::ANSWERS
      assert_includes @requests.last["messages"][0]["content"], Loader::LlmPrompts::ANSWERS
      assert_nil @requests.last["tools"]
      assert_equal %w[success success], LlmUsage.order(:created_at).last(2).map(&:outcome)
    end
  end

  test "#load should keep legitimate no-match source searches as successful empty lists" do
    stub_answers("No matching source posts were found.", '{"items":[]}')

    assert_equal [], Loader::LlmLoader.new(feed("Find source posts announcing a release today")).load
    assert_equal %w[success success], LlmUsage.order(:created_at).pluck(:outcome)
  end

  test "#load should preserve an uncertain answer through bounded JSON correction" do
    answer = "Not sure. Evidence is inconclusive. https://example.com/evidence"
    payload = { items: [{ body: answer, source_url: nil }] }.to_json
    stub_answers(answer, "#{payload},", payload)

    assert_equal answer, Loader::LlmLoader.new(feed).load.sole["body"]
    assert_equal 3, @requests.size
    assert_includes @requests.last["messages"].first["content"], "answers expressing"
    assert_includes @requests.last["messages"].last["content"], answer
    assert_equal %w[success schema_error success], LlmUsage.order(:created_at).pluck(:outcome)
  end
end
