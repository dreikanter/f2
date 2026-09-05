# Optional diagnostics for investigating provider behavior.
module LlmCapabilityProbe
  # Production's schema verbatim: a simplified copy qualifies a shape the app
  # never sends. The nullable `source_url` union is the part strict
  # structured-output modes reject.
  PROBE_SCHEMA = FeedProfile::UNIVERSAL_OUTPUT_SCHEMA

  # Stands in for production's stage system prompts (Loader::LlmPrompts). The
  # checks mirroring those stages carry it; `plain` stays bare so it isolates
  # reachability from the system channel `system_prompt` covers.
  PROBE_INSTRUCTIONS = "You are a content-gathering agent for a feed reader. " \
                       "Follow the task exactly and report only what you actually find."

  # The instructions contradict the obvious answer, so the expected reply is
  # unreachable unless the system channel arrived and was obeyed.
  SYSTEM_CHECK_WORD = "MARLIN".freeze
  SYSTEM_CHECK_INSTRUCTIONS = "You are a capability probe target. Whatever the user asks, " \
                              "reply with exactly one word: #{SYSTEM_CHECK_WORD}."
  SYSTEM_CHECK_PROMPT = "What is the capital of France? Answer in one word."

  # A fluent reply can still be a refusal ("I cannot browse the web, visit the
  # site yourself") — grounding checks must not read that as retrieval.
  REFUSAL_MARKERS = /(?:don't|do not) have the ability|(?:cannot|can't|unable to) (?:browse|access)|no ability to browse/i

  def self.refusal?(text)
    text.to_s.match?(REFUSAL_MARKERS)
  end

  # Mirrors production's structuring stage: fixed text in, strict JSON out. The
  # sample's last entry has no link of its own and the prompt asks for the null
  # that represents it, so the provider has to emit the union, not just accept it.
  STRUCTURE_PROMPT_PREFIX = "Convert the gathered web content below into the required JSON object. " \
                            "Use only what is present; do not invent items or fields. For an item with " \
                            "no single canonical link, set source_url to JSON null.\n\nGATHERED CONTENT:\n"
  SAMPLE_TEXT = <<~TEXT
    Post: "Rails 8.1 released" at https://example.com/blog/rails-8-1 — the release adds a faster boot path.
    Post: "SQLite in production" at https://example.com/blog/sqlite-prod — a guide to running SQLite at scale.
    Roundup: both posts above, summarized together — no link of its own.
  TEXT

  CLIENT_TOOLS_PROMPT = "Search for IANA's reserved documentation domains, fetch the top result with the " \
                        "fetch tool, and quote the exact text of that page's main heading."

  CLIENT_TOOLS_SCHEMA_PROMPT = "#{CLIENT_TOOLS_PROMPT} Return exactly one item: body set to that heading, " \
                               "source_url set to the page's URL.".freeze

  # Appears only on the fetched page — never in the prompt or the canned search
  # results — so quoting it requires having read fetched content. Keep it that
  # way when editing either.
  EXPECTED_HEADING = /example domain/i

  SEARCH_TOOL_NAME = LlmClient::Tools::WebSearch.new(provider: nil, credential: nil).name
  FETCH_TOOL_NAME = LlmClient::Tools::WebFetch.new.name

  # Stand-in for the production search tool: same wire shape, canned results, so
  # the loop can be driven without managed search credentials. The fetch tool
  # needs no stand-in — the production one is credential-free.
  class CannedWebSearch < RubyLLM::Tool
    description LlmClient::Tools::WebSearch.description
    param :query, desc: "Search query", required: true

    # Withholds the heading the check looks for: if a result disclosed it, a
    # model could pass by repeating the snippet without fetching anything.
    RESULTS = [
      { "title" => "IANA-managed Reserved Domains", "url" => "https://example.com/",
        "snippet" => "Names set aside by IANA for use in documentation. Open the page to read it." }
    ].freeze

    def initialize(budget: nil)
      super()
      @budget = budget
    end

    def name = SEARCH_TOOL_NAME

    # Results are canned, but every round is still a billed completion, so the
    # budget is spent as the production tool spends it. Serialized the same way
    # too, so the loop sees the same wire shape.
    def execute(query:)
      over_budget = @budget&.claim
      return over_budget if over_budget

      { results: RESULTS }.to_json
    end
  end

  class Runner
    CHECKS = %w[models plain system_prompt schema client_tools client_tools_schema].freeze

    def initialize(credential:, model:, checks: CHECKS)
      @credential = credential
      @model = model
      @checks = checks
      @results = []
    end

    # Returns { results:, passed: }. Every check is attempted; failures are
    # recorded, never raised — the job is to report what a provider does, not
    # to crash on it. `passed` is a summary; the per-check results are the
    # verdict (see docs/llm-provider-qualification.md).
    def run
      @checks.each { |check| record(check) { send("check_#{check}") } }
      { results: @results, passed: @results.none? { |r| r[:status] == "FAIL" } }
    end

    private

    def record(check)
      started = Time.current
      outcome = yield
      @results << { check: check, status: outcome[:status], note: outcome[:note],
                    evidence: outcome[:evidence], seconds: (Time.current - started).round(1) }
    rescue StandardError => e
      @results << { check: check, status: "FAIL", note: "#{e.class}: #{e.message.to_s[0, 300]}",
                    evidence: nil, seconds: (Time.current - started).round(1) }
    end

    # Exact IDs keep diagnostic results attached to the requested model.
    # nothing. Goes through the listing the app itself calls, so a pass means
    # the credential can also be validated. The listing is recorded as evidence.
    def check_models
      ids = LlmClient.new(@credential).available_models.map { |model| model["id"] }
      evidence = { model_ids: ids }
      return { status: "FAIL", note: "models endpoint returned no models", evidence: evidence } if ids.empty?

      served = ids.include?(@model)
      note = served ? "#{@model} served exactly (#{ids.size} models listed)" : "#{@model} not among #{ids.size} served ids"
      { status: served ? "PASS" : "FAIL", note: note, evidence: evidence }
    end

    def check_plain
      chat = @credential.chat(@model)
      text = chat.ask("Reply with the single word: pong").content.to_s
      pass(text.match?(/pong/i), "expected 'pong'", text) { "plain round trip" }
    end

    def check_system_prompt
      chat = @credential.chat(@model)
      chat.with_instructions(SYSTEM_CHECK_INSTRUCTIONS)
      text = chat.ask(SYSTEM_CHECK_PROMPT).content.to_s
      pass(honors_system_prompt?(text), "system instructions not honored verbatim", text) { "system prompt honored" }
    end

    # Only the word alone counts: a refusal that names it, or an answer that
    # also volunteers the real one, means the prompt arrived but wasn't obeyed.
    # Punctuation is ignored — a trailing period is formatting.
    def honors_system_prompt?(text)
      text.gsub(/[^[:alpha:]]/, "").casecmp?(SYSTEM_CHECK_WORD)
    end

    # Production's structure stage pairs STRUCTURE_SYSTEM with the schema, and
    # that pairing is its own wire shape: an OpenAI-compatible provider can
    # reject the system role RubyLLM defaults to, which a schema-only call
    # never exercises.
    def check_schema
      chat = @credential.chat(@model).with_schema(adapter.schema_payload(PROBE_SCHEMA))
      chat.with_instructions(PROBE_INSTRUCTIONS)
      apply_params(chat, schema: true, web: false)
      response = chat.ask(STRUCTURE_PROMPT_PREFIX + SAMPLE_TEXT)
      validate_items(response, expect_null_source_url: true)
    end

    # Production's gather step: system prompt plus the client-side tools driven
    # through a real multi-round loop.
    def check_client_tools
      client_tools_loop
    end

    # Production's combined shape: schema on the same chat as the tools. Schema
    # and tools can each work alone yet break together. A FAIL means the pair
    # needs two-step extraction (Adapter#combined_extraction?), not that it
    # fails qualification.
    def check_client_tools_schema
      client_tools_loop(schema: PROBE_SCHEMA)
    end

    def client_tools_loop(schema: nil)
      chat = client_tools_chat(schema)
      response = chat.ask(schema ? CLIENT_TOOLS_SCHEMA_PROMPT : CLIENT_TOOLS_PROMPT)
      answer = answer_text(response)
      rounds = tool_rounds(chat)
      evidence = { tool_rounds: rounds, answer: answer[0, 2000] }

      failure = tool_loop_failure(rounds) || grounding_failure(answer)
      return failure.merge(evidence: evidence) if failure
      return structured_result(response, rounds, evidence) if schema

      { status: "PASS", note: "#{rounds.size} tool calls, answer grounded in fetched page", evidence: evidence }
    end

    # Instances sharing one budget, as production builds them
    # (LlmClient::Adapter::Base#apply_web): the probe drives a paid API, and an
    # unqualified model is the likeliest to loop on a tool.
    def client_tools_chat(schema)
      chat = @credential.chat(@model)
      chat.with_instructions(PROBE_INSTRUCTIONS)
      chat.with_schema(adapter.schema_payload(schema)) if schema
      apply_params(chat, schema: !schema.nil?, web: true)
      budget = LlmClient::ToolBudget.new
      chat.with_tool(CannedWebSearch.new(budget: budget))
      chat.with_tool(LlmClient::Tools::WebFetch.new(budget: budget))
      chat
    end

    # The params production sends for the shape being probed, so a model is
    # qualified on the request the loader actually makes.
    def apply_params(chat, schema:, web:)
      params = adapter.params_for(@model, schema: schema, web: web)
      chat.with_params(**params) if params.present?
    end

    def grounding_failure(answer)
      return nil if EXPECTED_HEADING.match?(answer) && !LlmCapabilityProbe.refusal?(answer)

      { status: "FAIL", note: "tools ran but answer not grounded" }
    end

    def structured_result(response, rounds, evidence)
      result = validate_items(response)
      result.merge(note: "#{rounds.size} tool calls, grounded; #{result[:note]}",
                   evidence: evidence.merge(result[:evidence] || {}))
    end

    # Structured replies arrive as a Hash; serialize so grounding reads the same
    # way for both shapes.
    def answer_text(response)
      content = response.content
      content.is_a?(Hash) ? JSON.generate(content) : content.to_s
    end

    # The fetch must have returned the page itself: a refused URL, a wrong URL
    # or an HTTP error leaves the model nothing to ground on.
    def tool_loop_failure(rounds)
      names = rounds.map { |round| round[:name] }
      return { status: "FAIL", note: "search tool never called" } unless names.include?(SEARCH_TOOL_NAME)

      fetch = rounds.find { |round| round[:name] == FETCH_TOOL_NAME }
      return { status: "FAIL", note: "fetch tool never called" } if fetch.nil?
      return { status: "FAIL", note: "fetch returned no page content" } unless EXPECTED_HEADING.match?(fetch[:result])

      nil
    end

    # Pairs each tool call with the result the loop fed back, so a check can
    # assert on what a tool returned and not merely that it was called.
    def tool_rounds(chat)
      messages = Array(chat.try(:messages))
      results = messages.select { |message| message.try(:tool_result?) }.index_by(&:tool_call_id)
      messages.select { |message| message.try(:tool_call?) }
              .flat_map { |message| message.tool_calls.values }
              .map do |call|
                { name: call.name, arguments: call.arguments, result: results[call.id]&.content.to_s[0, 500] }
              end
    end

    def validate_items(response, expect_null_source_url: false)
      raw = response.content
      payload = raw.is_a?(Hash) ? raw : repair(JSON.parse(unwrap_json(raw.to_s)))
      errors = JSONSchemer.schema(PROBE_SCHEMA).validate(payload).to_a
      items = payload.is_a?(Hash) ? Array(payload["items"]) : []
      evidence = { items: items.first(3) }
      if errors.any?
        { status: "FAIL", note: "schema violation: #{errors.first['error']}", evidence: evidence }
      elsif items.empty?
        { status: "FAIL", note: "valid but empty items", evidence: evidence }
      elsif LlmCapabilityProbe.refusal?(JSON.generate(items))
        # A refusal wearing the schema would otherwise qualify a model for
        # gathering it never did.
        { status: "FAIL", note: "schema-valid but the items are a refusal", evidence: evidence }
      elsif expect_null_source_url && items.none? { |item| item["source_url"].nil? }
        # Accepting the union in the schema is not the same as emitting it, and
        # a digest feed depends on the null branch.
        { status: "FAIL", note: "schema-valid but no item emitted a null source_url", evidence: evidence }
      else
        { status: "PASS", note: "#{items.size} items, schema-valid", evidence: evidence }
      end
    rescue JSON::ParserError => e
      { status: "FAIL", note: "non-JSON response: #{e.message[0, 120]}", evidence: raw.to_s[0, 500] }
    end

    # Repairs structured output the way production does, so the probe doesn't
    # fail a model on a quirk the app already absorbs (Kimi fences its JSON).
    def unwrap_json(text)
      adapter.unwrap_json(text)
    end

    # Same root repairs production applies after parsing (a bare items array,
    # a double-encoded payload), for the same reason as unwrap_json.
    def repair(payload)
      LlmClient::PayloadRepair.repair(payload, PROBE_SCHEMA)
    end

    # The same adapter production builds its calls with, so schema strictness
    # and response repair are probed as they ship.
    def adapter
      @adapter ||= LlmClient::Adapter.for(@credential.provider)
    end

    def pass(condition, fail_note, evidence)
      { status: condition ? "PASS" : "FAIL", note: condition ? yield : fail_note, evidence: evidence.to_s[0, 2000] }
    end
  end
end
