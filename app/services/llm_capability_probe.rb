# Dev-time capability probe for LLM providers (spec 005 §5; issue #913).
#
# Live-verifies provider-native behavior through RubyLLM: plain calls,
# structured output, hosted search/fetch mechanisms, and one-call versus
# two-step extraction. These checks are deliberately separate from the
# production managed-search path, which uses LlmClient's client-side tools.
#
# The probe stays independent of LlmProvider and managed credentials so an
# unwired provider can be qualified before application integration. Keys
# come from the environment. Results — evidence included — are recorded as
# JobRun events and feed plan-03-provider-verification.md.
#
# Qualification rule (issue #1187): no (provider, model) pair enters
# LlmModelCapability without a probe run that covers the production call
# shape — a system prompt on the wire, the client-side tool loop, and the
# model id confirmed against the live models listing.
module LlmCapabilityProbe
  # Mirrors UNIVERSAL_OUTPUT_SCHEMA's shape (strict: additionalProperties false
  # everywhere — the Anthropic requirement confirmed live in Track 2).
  PROBE_SCHEMA = {
    "type" => "object",
    "properties" => {
      "items" => {
        "type" => "array",
        "items" => {
          "type" => "object",
          "properties" => {
            "uid" => { "type" => "string" },
            "title" => { "type" => "string" },
            "body" => { "type" => "string" },
            "source_url" => { "type" => "string" }
          },
          "required" => ["uid", "body", "source_url"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["items"],
    "additionalProperties" => false
  }.freeze

  GATHER_PROMPT = "Search the web for the latest two posts on the Ruby on Rails official blog " \
                  "(rubyonrails.org/blog). For each, report the title, its full URL, and a one-sentence summary."

  # Production always sends a system prompt (LlmClient#call's privileged
  # instruction channel), so the gathering checks carry one too — a pair must
  # not qualify on a call shape production never uses.
  PROBE_INSTRUCTIONS = "You are a content-gathering agent for a feed reader. " \
                       "Follow the task exactly and report only what you actually find."

  # The instructions contradict the obvious answer, so the reply can only
  # match by honoring the system channel. A wire-level rejection (Moonshot
  # 400s on role "developer") and silently dropped instructions both fail.
  SYSTEM_CHECK_WORD = "MARLIN".freeze
  SYSTEM_CHECK_INSTRUCTIONS = "You are a capability probe target. Whatever the user asks, " \
                              "reply with exactly one word: #{SYSTEM_CHECK_WORD}."
  SYSTEM_CHECK_PROMPT = "What is the capital of France? Answer in one word."

  # A reply can contain URLs and still be a refusal ("I cannot browse the
  # web... visit rubyonrails.org/blog yourself") — grounding checks must
  # treat that as no web access, not as evidence.
  REFUSAL_MARKERS = /(?:don't|do not) have the ability|(?:cannot|can't|unable to) (?:browse|access)|no ability to browse/i

  def self.refusal?(text)
    text.to_s.match?(REFUSAL_MARKERS)
  end
  STRUCTURE_PROMPT_PREFIX = "Convert the gathered web content below into the required JSON object. " \
                            "Use only what is present; do not invent items or fields.\n\nGATHERED CONTENT:\n"
  SAMPLE_TEXT = <<~TEXT
    Post: "Rails 8.1 released" at https://example.com/blog/rails-8-1 — the release adds a faster boot path.
    Post: "SQLite in production" at https://example.com/blog/sqlite-prod — a guide to running SQLite at scale.
  TEXT

  CLIENT_TOOLS_PROMPT = "Search for IANA's reserved documentation domains, fetch the top result with the " \
                        "fetch tool, and quote the exact text of that page's main heading."

  CLIENT_TOOLS_SCHEMA_PROMPT = "#{CLIENT_TOOLS_PROMPT} Return exactly one item: body set to that heading, " \
                               "uid and source_url set to the page's URL.".freeze

  # The heading lives only on the fetched page — deliberately absent from the
  # prompt and from the canned search results — so quoting it is evidence the
  # model read fetched content rather than echoing what it was already told.
  EXPECTED_HEADING = /example domain/i

  # Wire names the production tools present to the model; the client-tools
  # check matches the loop's observed tool calls against these.
  SEARCH_TOOL_NAME = LlmClient::Tools::WebSearch.new(provider: nil, credential: nil).name
  FETCH_TOOL_NAME = LlmClient::Tools::WebFetch.new.name

  # Probe-local stand-in for the production search tool: identical wire shape
  # (name, description, parameter) but canned results pointing at fixed real
  # URLs, so the tool loop can be qualified without managed search
  # credentials. The follow-up fetch is the real production tool, which is
  # credential-free.
  class CannedWebSearch < RubyLLM::Tool
    description LlmClient::Tools::WebSearch.description
    param :query, desc: "Search query", required: true

    # Withholds the heading the check looks for: if a result disclosed it, a
    # model could pass by repeating the snippet without fetching anything.
    RESULTS = [
      { "title" => "IANA-managed Reserved Domains", "url" => "https://example.com/",
        "snippet" => "Names set aside by IANA for use in documentation. Open the page to read it." }
    ].freeze

    def name = SEARCH_TOOL_NAME

    def execute(query:)
      { results: RESULTS }
    end
  end

  # Moonshot's server-executed web search is invoked through a builtin tool
  # the client must acknowledge by echoing the arguments back. Modeled as a
  # RubyLLM function tool so the gem's tool loop performs that round trip.
  class MoonshotWebSearchEcho < RubyLLM::Tool
    description "Builtin server-side web search"
    param :query, desc: "Search query", required: false

    def name = "$web_search"

    def execute(**args)
      args
    end
  end

  class Provider
    attr_reader :key

    def initialize(key)
      @key = key
    end

    def context
      @context ||= RubyLLM.context { |config| configure(config) }
    end

    def chat(model)
      context.chat(model: model, provider: ruby_llm_provider, assume_model_exists: assume_model_exists?)
    end

    # The provider's live models listing, resolved the way LlmClient does it
    # (registry names don't always match RubyLLM provider keys).
    def list_models
      RubyLLM::Provider.resolve(ruby_llm_provider).new(context.config).list_models
    end

    def assume_model_exists? = false
    def web_fetch_params(_model) = nil
    def prepare_web(_chat) = nil

    class Anthropic < Provider
      def self.env_key = "ANTHROPIC_API_KEY"

      def configure(config)
        config.anthropic_api_key = ENV.fetch(self.class.env_key)
      end

      def ruby_llm_provider = :anthropic

      # Combined hosted-tool shape is probe-local. Production uses the managed
      # client-side search and fetch tools instead.
      def web_params(model)
        { tools: web_search_params(model)[:tools] + web_fetch_params(model)[:tools] }
      end

      def web_search_params(_model)
        { tools: [{ type: "web_search_20260209", name: "web_search" }] }
      end

      def web_fetch_params(_model)
        { tools: [{ type: "web_fetch_20260209", name: "web_fetch", citations: { enabled: false } }] }
      end
    end

    class Moonshot < Provider
      def self.env_key = "MOONSHOT_API_KEY"

      def configure(config)
        config.openai_api_key = ENV.fetch(self.class.env_key)
        config.openai_api_base = ENV.fetch("MOONSHOT_API_BASE", "https://api.moonshot.ai/v1")
        # Mirror production (LlmProvider#configure): Moonshot rejects the
        # "developer" role RubyLLM sends by default, so the probe must use
        # the same wire shape or its results won't transfer.
        config.openai_use_system_role = true
      end

      def ruby_llm_provider = :openai
      def assume_model_exists? = true

      def web_params(_model)
        { tools: [{ type: "builtin_function", function: { name: "$web_search" } }] }
      end

      alias web_search_params web_params

      # The builtin needs the echo round trip; register the tool so RubyLLM's
      # loop answers the tool call instead of failing on an unknown tool.
      def prepare_web(chat)
        chat.with_tool(MoonshotWebSearchEcho)
      end
    end

    REGISTRY = { "anthropic" => Anthropic, "moonshot" => Moonshot }.freeze

    def self.build(key)
      klass = REGISTRY.fetch(key) { raise ArgumentError, "Unknown provider '#{key}'. Known: #{REGISTRY.keys.join(', ')}" }
      klass.new(key)
    end

    def self.configured?(key)
      REGISTRY.key?(key) && ENV[REGISTRY.fetch(key).env_key].present?
    end
  end

  class Runner
    CHECKS = %w[models plain system_prompt schema web_search web_fetch two_step combined
                client_tools client_tools_schema].freeze

    def initialize(provider:, model:, checks: CHECKS)
      @provider = provider
      @model = model
      @checks = checks
      @results = []
    end

    # Returns { results:, passed: }. Every check is attempted; failures are
    # recorded, never raised — the probe's job is to report what a provider
    # does, not to crash on it. Evidence rides along in each result so the
    # caller can persist everything (no separate transcript to chase).
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

    # Records the authenticated models listing as evidence and confirms the
    # probed id is served verbatim — the capability matrix gates on exact
    # string match, so a near-miss id qualifies nothing.
    def check_models
      ids = @provider.list_models.map(&:id)
      evidence = { model_ids: ids }
      return { status: "FAIL", note: "models endpoint returned no models", evidence: evidence } if ids.empty?

      served = ids.include?(@model)
      note = served ? "#{@model} served exactly (#{ids.size} models listed)" : "#{@model} not among #{ids.size} served ids"
      { status: served ? "PASS" : "FAIL", note: note, evidence: evidence }
    end

    def check_plain
      chat = @provider.chat(@model)
      text = chat.ask("Reply with the single word: pong").content.to_s
      pass(text.match?(/pong/i), "expected 'pong'", text) { "plain round trip" }
    end

    def check_system_prompt
      chat = @provider.chat(@model)
      chat.with_instructions(SYSTEM_CHECK_INSTRUCTIONS)
      text = chat.ask(SYSTEM_CHECK_PROMPT).content.to_s
      pass(honors_system_prompt?(text), "system instructions not honored verbatim", text) { "system prompt honored" }
    end

    # The instructions ask for exactly one word, so only that word counts:
    # a refusal that names it, or an answer that also volunteers the user
    # prompt's answer, means the channel was received but not obeyed.
    # Punctuation and surrounding whitespace are ignored — a trailing period
    # is formatting, not a second thought.
    def honors_system_prompt?(text)
      text.gsub(/[^[:alpha:]]/, "").casecmp?(SYSTEM_CHECK_WORD)
    end

    def check_schema
      chat = @provider.chat(@model).with_schema(PROBE_SCHEMA)
      response = chat.ask(STRUCTURE_PROMPT_PREFIX + SAMPLE_TEXT)
      validate_items(response)
    end

    def check_web_search
      chat = @provider.chat(@model)
      @provider.prepare_web(chat)
      chat.with_params(**@provider.web_search_params(@model))
      text = chat.ask(GATHER_PROMPT).content.to_s
      return { status: "FAIL", note: "model reports no web access", evidence: text[0, 2000] } if LlmCapabilityProbe.refusal?(text)

      pass(text.match?(%r{https?://}) && text.length > 80, "no URLs in response", text) { "web search grounding" }
    end

    def check_web_fetch
      params = @provider.web_fetch_params(@model)
      return { status: "SKIP", note: "provider declares no web-fetch mechanism", evidence: nil } if params.nil?

      chat = @provider.chat(@model).with_params(**params)
      text = chat.ask("Fetch https://example.com/ and quote the exact text of its <h1> heading.").content.to_s
      pass(text.match?(/example domain/i), "page content not quoted", text) { "web fetch grounding" }
    end

    # Provider-native two-step capability comparison. Both calls carry system
    # instructions the way production stage calls do.
    def check_two_step
      gather = @provider.chat(@model)
      gather.with_instructions(PROBE_INSTRUCTIONS)
      @provider.prepare_web(gather)
      gather.with_params(**@provider.web_params(@model))
      gathered = gather.ask(GATHER_PROMPT).content.to_s
      return { status: "FAIL", note: "gather returned blank", evidence: nil } if gathered.strip.empty?

      structure = @provider.chat(@model).with_schema(PROBE_SCHEMA)
      structure.with_instructions(PROBE_INSTRUCTIONS)
      validate_items(structure.ask(STRUCTURE_PROMPT_PREFIX + gathered), gathered: gathered)
    end

    # Provider-native combined capability check — recorded as evidence;
    # PASS here means "works combined", which would simplify the architecture.
    def check_combined
      chat = @provider.chat(@model).with_schema(PROBE_SCHEMA)
      chat.with_instructions(PROBE_INSTRUCTIONS)
      @provider.prepare_web(chat)
      chat.with_params(**@provider.web_params(@model))
      validate_items(chat.ask(GATHER_PROMPT))
    end

    # The production mechanism end to end: a system prompt plus the
    # client-side search and fetch function tools driven through a real
    # multi-round loop. The observed tool calls plus an answer grounded in
    # the fetched page are the evidence that the model drives client tools.
    # This is production's gather shape for two-step providers (LlmLoader).
    def check_client_tools
      client_tools_loop
    end

    # Production's combined shape (LlmLoader#extract when the adapter reports
    # `combined_extraction?`): the output schema rides on the same chat as the
    # client-side tools. Schema and tools can each work alone yet break
    # together, so a pair qualified only by the checks above could still fail
    # on a real feed load. A FAIL here reads as "use two-step", not as a
    # disqualification — same as the provider-native `combined` check.
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

    def client_tools_chat(schema)
      chat = @provider.chat(@model)
      chat.with_instructions(PROBE_INSTRUCTIONS)
      chat.with_schema(schema) if schema
      chat.with_tool(CannedWebSearch)
      chat.with_tool(LlmClient::Tools::WebFetch)
      chat
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

    # Structured replies arrive as a Hash; serialize so grounding reads the
    # same way for both shapes.
    def answer_text(response)
      content = response.content
      content.is_a?(Hash) ? JSON.generate(content) : content.to_s
    end

    # Both tools must appear in the loop, and the fetch must have returned the
    # page itself: a refused URL, a wrong URL or an HTTP error leaves nothing
    # to ground on, and the heading appears nowhere else in the conversation.
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

    def validate_items(response, gathered: nil)
      raw = response.content
      payload = raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
      errors = JSONSchemer.schema(PROBE_SCHEMA).validate(payload).to_a
      items = payload.is_a?(Hash) ? Array(payload["items"]) : []
      evidence = { items: items.first(3), gathered_preview: gathered&.slice(0, 2000) }.compact
      if errors.any?
        { status: "FAIL", note: "schema violation: #{errors.first['error']}", evidence: evidence }
      elsif items.empty?
        { status: "FAIL", note: "valid but empty items", evidence: evidence }
      else
        { status: "PASS", note: "#{items.size} items, schema-valid", evidence: evidence }
      end
    rescue JSON::ParserError => e
      { status: "FAIL", note: "non-JSON response: #{e.message[0, 120]}", evidence: raw.to_s[0, 500] }
    end

    def pass(condition, fail_note, evidence)
      { status: condition ? "PASS" : "FAIL", note: condition ? yield : fail_note, evidence: evidence.to_s[0, 2000] }
    end
  end
end
