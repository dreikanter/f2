require "test_helper"

class KimiExperimentTest < ActiveSupport::TestCase
  def tool_call_response
    { status: 200, body: {
      "choices" => [{ "finish_reason" => "tool_calls", "message" => {
        "role" => "assistant", "content" => "",
        "tool_calls" => [{ "id" => "c1", "type" => "function",
                           "function" => { "name" => "$web_search", "arguments" => '{"query":"rails blog"}' } }]
      } }]
    } }
  end

  def content_response(text)
    { status: 200, body: { "choices" => [{ "finish_reason" => "stop", "message" => { "content" => text } }] } }
  end

  test ".classify_json should distinguish clean, fenced, and invalid output" do
    assert_equal "clean_json", KimiExperiment.classify_json('{"items": []}')
    assert_equal "fenced_json", KimiExperiment.classify_json("```json\n{\"items\": []}\n```")
    assert_equal "fenced_json", KimiExperiment.classify_json("```\n{\"a\": 1}\n```")
    assert_equal "invalid", KimiExperiment.classify_json("I cannot produce JSON")
    assert_equal "invalid", KimiExperiment.classify_json("```json\nnot json\n```")
  end

  test ".grounded? should reject refusals that happen to contain URLs" do
    refusal = "I don't have the ability to browse the web. Visit https://rubyonrails.org/blog yourself."
    assert_not KimiExperiment.grounded?(refusal)
    assert KimiExperiment.grounded?("Latest post: https://rubyonrails.org/2025/12/26/this-week-in-rails")
    assert_not KimiExperiment.grounded?("no links here")
  end

  test ".grounded? should reject fetch-failure prose that still contains the blog URL" do
    fetch_failure = "I encountered a 301 redirect when trying to fetch the blog. " \
                    "Check it directly at https://rubyonrails.org/blog."
    assert_not KimiExperiment.grounded?(fetch_failure)
  end

  test ".web_search_steps should echo tool-call arguments back and record both rounds" do
    payloads = []
    responses = [tool_call_response, content_response("Found: https://rubyonrails.org/2025/12/26")]
    fake = lambda do |payload|
      payloads << payload
      responses.shift
    end

    steps = KimiExperiment.stub(:raw_chat, fake) { KimiExperiment.web_search_steps }

    assert_equal 2, steps.size
    assert_equal "tool_calls", steps.first[:finish_reason]
    assert steps.first[:tool_calls].present?
    assert steps.second[:grounded]

    echo = payloads.second[:messages].last
    assert_equal "tool", echo[:role]
    assert_equal "c1", echo[:tool_call_id]
    assert_equal '{"query":"rails blog"}', echo[:content]
    assert_not payloads.first.key?(:tool_choice)
  end

  test ".web_search_steps with force_tool should set tool_choice only on the first round" do
    payloads = []
    responses = [tool_call_response, content_response("done")]
    fake = lambda do |payload|
      payloads << payload
      responses.shift
    end

    KimiExperiment.stub(:raw_chat, fake) { KimiExperiment.web_search_steps(force_tool: true) }

    assert_equal "$web_search", payloads.first.dig(:tool_choice, :function, :name)
    assert_not payloads.second.key?(:tool_choice)
  end

  test ".web_search_steps should stop after one round when the model ignores the tool" do
    steps = KimiExperiment.stub(:raw_chat, ->(_p) { content_response("I cannot browse the web") }) do
      KimiExperiment.web_search_steps
    end

    assert_equal 1, steps.size
    assert_not steps.first[:grounded]
  end

  test ".structured_output_attempts should try each response_format mode with repeats" do
    payloads = []
    fake = lambda do |payload|
      payloads << payload
      content_response('{"items": []}')
    end

    attempts = KimiExperiment.stub(:raw_chat, fake) { KimiExperiment.structured_output_attempts(repeats: 2) }

    assert_equal 6, attempts.size
    assert_equal %w[none json_object json_schema], attempts.map { |a| a[:mode] }.uniq
    assert attempts.all? { |a| a[:outcome] == "clean_json" }
    formats = payloads.map { |p| p.dig(:response_format, :type) }
    assert_equal [nil, nil, "json_object", "json_object", "json_schema", "json_schema"], formats
  end

  test ".structured_output_attempts should record error bodies on non-200 responses" do
    fake = ->(_p) { { status: 400, body: { "error" => { "message" => "bad tool_choice" } } } }

    attempts = KimiExperiment.stub(:raw_chat, fake) { KimiExperiment.structured_output_attempts(repeats: 1) }

    assert attempts.all? { |a| a[:status] == 400 }
    assert_match(/bad tool_choice/, attempts.first[:error])
  end
end
