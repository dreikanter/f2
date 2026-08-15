require "test_helper"

class LlmCapabilityProbeTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:content)

  FakeToolCallMessage = Struct.new(:tool_calls) do
    def tool_call? = true
    def tool_result? = false
  end

  FakeToolResultMessage = Struct.new(:tool_call_id, :content) do
    def tool_call? = false
    def tool_result? = true
  end

  class FakeChat
    attr_reader :instructions, :schema, :tools

    def initialize(response, tool_rounds: [])
      @response = response
      @tool_rounds = tool_rounds
      @tools = []
    end

    def with_params(**) = self

    def with_schema(schema)
      @schema = schema
      self
    end

    def with_tool(tool)
      @tools << tool
      self
    end

    def with_instructions(text)
      @instructions = text
      self
    end

    def ask(_prompt)
      raise @response if @response.is_a?(StandardError)

      FakeResponse.new(@response)
    end

    def messages
      @tool_rounds.flat_map.with_index do |round, index|
        call = RubyLLM::ToolCall.new(id: index.to_s, name: round[:name], arguments: { "url" => "https://example.com/" })
        [FakeToolCallMessage.new({ call.id => call }), FakeToolResultMessage.new(call.id, round[:result])]
      end
    end
  end

  FakeModel = Struct.new(:id)

  class FakeProvider
    attr_reader :key, :chats

    def initialize(responses, models: [], tool_rounds: [])
      @responses = responses.is_a?(Array) ? responses.dup : [responses]
      @models = models
      @tool_rounds = tool_rounds
      @chats = []
      @key = "fake"
    end

    def chat(_model)
      FakeChat.new(@responses.shift, tool_rounds: @tool_rounds).tap { |chat| @chats << chat }
    end
    def list_models = @models.map { |id| FakeModel.new(id) }
    def unwrap_json(text) = LlmClient::Adapter::Moonshot.new.unwrap_json(text)
  end

  def run_checks(responses, checks, models: [], tool_rounds: [])
    provider = FakeProvider.new(responses, models: models, tool_rounds: tool_rounds)
    LlmCapabilityProbe::Runner.new(provider: provider, model: "test-model", checks: checks).run
  end

  FETCHED_PAGE = "Example Domain This domain is for use in illustrative examples in documents.".freeze

  def full_tool_loop(fetch_result: FETCHED_PAGE)
    [{ name: LlmCapabilityProbe::SEARCH_TOOL_NAME, result: "canned results" },
     { name: LlmCapabilityProbe::FETCH_TOOL_NAME, result: fetch_result }]
  end

  def valid_payload
    { "items" => [{ "uid" => "u1", "body" => "b", "source_url" => "https://example.com/p" },
                  { "body" => "A summary of several sources", "source_url" => nil }] }
  end

  def digest_payload
    { "items" => [{ "body" => "A summary of several sources", "source_url" => nil }] }
  end

  def linked_only_payload
    { "items" => [{ "body" => "b", "source_url" => "https://example.com/p" }] }
  end

  def grounded_payload
    { "items" => [{ "uid" => "https://example.com/", "body" => "Example Domain",
                    "source_url" => "https://example.com/" }] }
  end

  test "#run should pass the models check when the probed id is served exactly" do
    outcome = run_checks([], ["models"], models: %w[other-model test-model])

    assert outcome[:passed]
    assert_equal "PASS", outcome[:results].first[:status]
    assert_equal %w[other-model test-model], outcome[:results].first[:evidence][:model_ids]
  end

  test "#run should fail the models check when the probed id is not served" do
    outcome = run_checks([], ["models"], models: %w[test-model-v2])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_match(/not among 1 served ids/, outcome[:results].first[:note])
  end

  test "#run should fail the models check on an empty listing" do
    outcome = run_checks([], ["models"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_match(/no models/, outcome[:results].first[:note])
  end

  test "#run should pass the plain check on a pong reply" do
    outcome = run_checks("pong", ["plain"])

    assert outcome[:passed]
    assert_equal "PASS", outcome[:results].first[:status]
  end

  test "#run should fail the plain check on an unexpected reply" do
    outcome = run_checks("hello", ["plain"])

    assert_not outcome[:passed]
    assert_equal "FAIL", outcome[:results].first[:status]
  end

  test "#run should pass the system prompt check when instructions are honored" do
    outcome = run_checks("MARLIN", ["system_prompt"])

    assert outcome[:passed]
    assert_equal "PASS", outcome[:results].first[:status]
  end

  test "#run should pass the system prompt check ignoring punctuation and whitespace" do
    outcome = run_checks("  Marlin.\n", ["system_prompt"])

    assert_equal "PASS", outcome[:results].first[:status]
  end

  test "#run should fail the system prompt check when instructions are ignored" do
    outcome = run_checks("Paris", ["system_prompt"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_equal "system instructions not honored verbatim", outcome[:results].first[:note]
  end

  test "#run should fail the system prompt check on a hedged reply naming both answers" do
    outcome = run_checks("You asked for MARLIN, but the capital is Paris.", ["system_prompt"])

    assert_equal "FAIL", outcome[:results].first[:status]
  end

  test "#run should fail the system prompt check on a refusal that names the word" do
    outcome = run_checks("I cannot follow the instruction to reply MARLIN.", ["system_prompt"])

    assert_equal "FAIL", outcome[:results].first[:status]
  end

  test "#run should pass the schema check on schema-valid items" do
    outcome = run_checks(valid_payload, ["schema"])

    assert_equal "PASS", outcome[:results].first[:status]
    assert_match(/2 items/, outcome[:results].first[:note])
  end

  test "#run should fail the schema check on a schema violation" do
    payload = { "items" => [{ "uid" => "u1", "body" => "b", "source_url" => "x", "extra" => 1 }] }
    outcome = run_checks(payload, ["schema"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_match(/schema violation/, outcome[:results].first[:note])
  end

  # The union is what a strict structured-output mode is most likely to reject,
  # so the check has to be running production's schema, not a copy of it.
  test "PROBE_SCHEMA should be the production output schema" do
    assert_same FeedProfile::UNIVERSAL_OUTPUT_SCHEMA, LlmCapabilityProbe::PROBE_SCHEMA
  end

  test "#run should pass the schema check on a digest item with a null source_url" do
    outcome = run_checks(digest_payload, ["schema"])

    assert_equal "PASS", outcome[:results].first[:status]
  end

  # Accepting the union in the schema is not the same as emitting it, and the
  # digest regime is the null branch.
  test "#run should fail the schema check when no item emitted a null source_url" do
    outcome = run_checks(linked_only_payload, ["schema"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_equal "schema-valid but no item emitted a null source_url", outcome[:results].first[:note]
  end

  # Only the schema check asks for the linkless roundup — the client-tools
  # prompt asks for one item with the fetched page's own URL.
  test "#run should not require a null source_url from client_tools_schema" do
    outcome = run_checks(grounded_payload, ["client_tools_schema"], tool_rounds: full_tool_loop)

    assert_equal "PASS", outcome[:results].first[:status]
  end

  test "#run should fail the schema check when a required field is missing" do
    outcome = run_checks({ "items" => [{ "body" => "b" }] }, ["schema"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_match(/schema violation/, outcome[:results].first[:note])
  end

  test "#run should fail the schema check on empty items" do
    outcome = run_checks({ "items" => [] }, ["schema"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_match(/empty items/, outcome[:results].first[:note])
  end

  test "#run should pass the schema check on fenced JSON the app unwraps" do
    outcome = run_checks("```json\n#{JSON.generate(valid_payload)}\n```", ["schema"])

    assert_equal "PASS", outcome[:results].first[:status]
  end

  test "#run should fail the schema check when schema-valid items are a refusal" do
    payload = { "items" => [{ "uid" => "u1", "source_url" => "https://example.com/",
                              "body" => "I cannot browse the live web, so I am unable to retrieve the posts." }] }
    outcome = run_checks(payload, ["schema"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_equal "schema-valid but the items are a refusal", outcome[:results].first[:note]
  end

  test "#run should fail the schema check on a non-JSON reply" do
    outcome = run_checks("not json at all", ["schema"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_match(/non-JSON/, outcome[:results].first[:note])
  end

  test "#run should fail the client tools check when the search tool is never called" do
    outcome = run_checks("Example Domain", ["client_tools"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_equal "search tool never called", outcome[:results].first[:note]
  end

  test "#run should fail the client tools check when the fetch tool is never called" do
    outcome = run_checks("Example Domain", ["client_tools"],
                         tool_rounds: [{ name: LlmCapabilityProbe::SEARCH_TOOL_NAME, result: "canned results" }])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_equal "fetch tool never called", outcome[:results].first[:note]
  end

  test "#run should fail the client tools check when the fetch returned no page content" do
    outcome = run_checks("The heading is Example Domain.", ["client_tools"],
                         tool_rounds: full_tool_loop(fetch_result: '{"error":"HTTP 403"}'))

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_equal "fetch returned no page content", outcome[:results].first[:note]
  end

  test "#run should pass the client tools check on a full loop with a grounded answer" do
    outcome = run_checks('The main heading reads: "Example Domain"', ["client_tools"], tool_rounds: full_tool_loop)

    assert_equal "PASS", outcome[:results].first[:status]
    assert_match(/2 tool calls/, outcome[:results].first[:note])
    assert_equal [LlmCapabilityProbe::SEARCH_TOOL_NAME, LlmCapabilityProbe::FETCH_TOOL_NAME],
                 outcome[:results].first[:evidence][:tool_rounds].map { |round| round[:name] }
  end

  test "#run should fail the client tools check when tools ran but the answer is not grounded" do
    outcome = run_checks("I could not determine the heading.", ["client_tools"], tool_rounds: full_tool_loop)

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_equal "tools ran but answer not grounded", outcome[:results].first[:note]
  end

  test "canned web search should present the production search tool's wire shape" do
    tool = LlmCapabilityProbe::CannedWebSearch.new
    production = LlmClient::Tools::WebSearch.new(provider: nil, credential: nil)

    assert_equal production.name, tool.name
    assert_equal production.description, tool.description
    assert_equal %i[query], tool.parameters.keys
  end

  test "canned web search should return fixed real URLs without touching a search provider" do
    result = JSON.parse(LlmCapabilityProbe::CannedWebSearch.new.execute(query: "anything"))

    assert_equal ["https://example.com/"], result["results"].map { |r| r["url"] }
  end

  test "#run should attach the schema and both client tools to one chat for client_tools_schema" do
    provider = FakeProvider.new(grounded_payload, tool_rounds: full_tool_loop)
    LlmCapabilityProbe::Runner.new(provider: provider, model: "test-model", checks: ["client_tools_schema"]).run
    chat = provider.chats.first

    assert_equal LlmCapabilityProbe::PROBE_SCHEMA, chat.schema
    assert_equal [LlmCapabilityProbe::CannedWebSearch, LlmClient::Tools::WebFetch], chat.tools.map(&:class)
    assert_equal LlmCapabilityProbe::PROBE_INSTRUCTIONS, chat.instructions
  end

  # An unqualified model is the likeliest one to loop, and the probe drives a
  # paid API, so it bounds the loop the way a feed run does.
  test "#run should bound the client tools loop with one budget shared by both tools" do
    provider = FakeProvider.new("The main heading reads: Example Domain", tool_rounds: full_tool_loop)
    LlmCapabilityProbe::Runner.new(provider: provider, model: "test-model", checks: ["client_tools"]).run

    budgets = provider.chats.first.tools.map { |tool| tool.instance_variable_get(:@budget) }

    assert_instance_of LlmClient::ToolBudget, budgets.first
    assert_same budgets.first, budgets.last
  end

  test "the canned search should spend the shared budget like the production tool" do
    budget = LlmClient::ToolBudget.new(rounds: 1, grace: 0)
    search = LlmCapabilityProbe::CannedWebSearch.new(budget: budget)

    assert_equal ["https://example.com/"], JSON.parse(search.execute(query: "first"))["results"].map { |r| r["url"] }
    assert_instance_of RubyLLM::Tool::Halt, search.execute(query: "second")
  end

  # Production never sends a schema without a system prompt, and that pairing is
  # its own wire shape — a schema-only call would not catch a rejected role.
  test "#run should send a system prompt alongside the schema" do
    provider = FakeProvider.new(valid_payload)
    LlmCapabilityProbe::Runner.new(provider: provider, model: "test-model", checks: ["schema"]).run

    assert_equal LlmCapabilityProbe::PROBE_INSTRUCTIONS, provider.chats.first.instructions
  end

  test "#run should leave the plain check bare so it isolates the round trip" do
    provider = FakeProvider.new("pong")
    LlmCapabilityProbe::Runner.new(provider: provider, model: "test-model", checks: ["plain"]).run

    assert_nil provider.chats.first.instructions
  end

  test "#run should leave the plain client tools check unstructured" do
    provider = FakeProvider.new("The main heading reads: Example Domain", tool_rounds: full_tool_loop)
    LlmCapabilityProbe::Runner.new(provider: provider, model: "test-model", checks: ["client_tools"]).run

    assert_nil provider.chats.first.schema
  end

  test "#run should pass client_tools_schema on a grounded schema-valid payload" do
    outcome = run_checks(grounded_payload, ["client_tools_schema"], tool_rounds: full_tool_loop)

    assert_equal "PASS", outcome[:results].first[:status]
    assert_match(/2 tool calls, grounded; 1 items, schema-valid/, outcome[:results].first[:note])
    assert_equal 2, outcome[:results].first[:evidence][:tool_rounds].size
  end

  test "#run should fail client_tools_schema when the grounded payload violates the schema" do
    payload = { "items" => [grounded_payload["items"].first.merge("extra" => 1)] }
    outcome = run_checks(payload, ["client_tools_schema"], tool_rounds: full_tool_loop)

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_match(/schema violation/, outcome[:results].first[:note])
  end

  test "#run should fail client_tools_schema when the payload is not grounded in the fetched page" do
    payload = { "items" => [{ "uid" => "u1", "body" => "Something else", "source_url" => "https://example.com/" }] }
    outcome = run_checks(payload, ["client_tools_schema"], tool_rounds: full_tool_loop)

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_equal "tools ran but answer not grounded", outcome[:results].first[:note]
  end

  test "the client tools check should not disclose the expected heading outside the fetched page" do
    canned = JSON.generate(LlmCapabilityProbe::CannedWebSearch.new.execute(query: "anything"))

    assert_no_match LlmCapabilityProbe::EXPECTED_HEADING, canned
    assert_no_match LlmCapabilityProbe::EXPECTED_HEADING, LlmCapabilityProbe::CLIENT_TOOLS_PROMPT
    assert_no_match LlmCapabilityProbe::EXPECTED_HEADING, LlmCapabilityProbe::PROBE_INSTRUCTIONS
  end

  test "#run should record an exception as a failed check" do
    outcome = run_checks(RuntimeError.new("boom"), ["plain"])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_match(/RuntimeError: boom/, outcome[:results].first[:note])
  end

  test ".build should raise on an unknown provider" do
    error = assert_raises(ArgumentError) { LlmCapabilityProbe::Provider.build("nope") }
    assert_match(/Unknown provider/, error.message)
  end

  test ".configured? should reflect presence of the provider env key" do
    original = ENV.fetch("MOONSHOT_API_KEY", nil)
    ENV["MOONSHOT_API_KEY"] = nil
    assert_not LlmCapabilityProbe::Provider.configured?("moonshot")

    ENV["MOONSHOT_API_KEY"] = "k"
    assert LlmCapabilityProbe::Provider.configured?("moonshot")
    assert_not LlmCapabilityProbe::Provider.configured?("nope")
  ensure
    ENV["MOONSHOT_API_KEY"] = original
  end

  test "checks should cover only what production calls" do
    assert_equal %w[models plain system_prompt schema client_tools client_tools_schema],
                 LlmCapabilityProbe::Runner::CHECKS
  end

  test "moonshot provider should configure the same system-role flag as production" do
    original = ENV.fetch("MOONSHOT_API_KEY", nil)
    ENV["MOONSHOT_API_KEY"] = "k"
    config = Struct.new(:openai_api_key, :openai_api_base, :openai_use_system_role).new

    LlmCapabilityProbe::Provider.build("moonshot").configure(config)

    assert config.openai_use_system_role
  ensure
    ENV["MOONSHOT_API_KEY"] = original
  end

  test "probe providers should unwrap structured output the way production does" do
    assert_equal '{"a":1}', LlmCapabilityProbe::Provider.build("moonshot").unwrap_json("```json\n{\"a\":1}\n```")
    assert_equal '{"a":1}', LlmCapabilityProbe::Provider.build("anthropic").unwrap_json('{"a":1}')
  end
end
