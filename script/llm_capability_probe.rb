# frozen_string_literal: true

# Dev-time capability probe for LLM providers (spec 005 §5; issue #913).
#
# Live-verifies that a (provider, model) pair delivers what the AI engine
# needs *through RubyLLM*, using the exact production call shapes from
# LlmClient / Loader::LlmLoader: plain call, schema-only, web-search-only,
# web-fetch-only, the two-step gather→structure pipeline, and (as evidence
# for the two-step rationale) schema+web combined in one call.
#
# Standalone on purpose — no Rails, no DB — so an unwired provider can be
# qualified before any app code exists for it. Matrix membership decisions
# and raw transcripts feed plan-03-provider-verification.md.
#
# Usage:
#   bundle exec ruby script/llm_capability_probe.rb --provider anthropic --model claude-sonnet-4-5
#   bundle exec ruby script/llm_capability_probe.rb --provider moonshot --model kimi-k2.5 --checks web_search,two_step
#
# Keys via env: ANTHROPIC_API_KEY, MOONSHOT_API_KEY (MOONSHOT_API_BASE to override).

require "ruby_llm"
require "json_schemer"
require "json"
require "optparse"
require "fileutils"

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
  STRUCTURE_PROMPT_PREFIX = "Convert the gathered web content below into the required JSON object. " \
                            "Use only what is present; do not invent items or fields.\n\nGATHERED CONTENT:\n"
  SAMPLE_TEXT = <<~TEXT
    Post: "Rails 8.1 released" at https://example.com/blog/rails-8-1 — the release adds a faster boot path.
    Post: "SQLite in production" at https://example.com/blog/sqlite-prod — a guide to running SQLite at scale.
  TEXT

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

    def assume_model_exists? = false
    def web_fetch_params(_model) = nil
    def prepare_web(_chat) = nil

    class Anthropic < Provider
      def configure(config)
        config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY")
      end

      def ruby_llm_provider = :anthropic

      # Production shape: LlmClient::Adapter::Anthropic#web_params.
      def web_params(_model)
        {
          tools: [
            { type: "web_search_20260209", name: "web_search" },
            { type: "web_fetch_20260209", name: "web_fetch", citations: { enabled: false } }
          ]
        }
      end

      def web_search_params(_model)
        { tools: [{ type: "web_search_20260209", name: "web_search" }] }
      end

      def web_fetch_params(_model)
        { tools: [{ type: "web_fetch_20260209", name: "web_fetch", citations: { enabled: false } }] }
      end
    end

    class Moonshot < Provider
      def configure(config)
        config.openai_api_key = ENV.fetch("MOONSHOT_API_KEY")
        config.openai_api_base = ENV.fetch("MOONSHOT_API_BASE", "https://api.moonshot.ai/v1")
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
      klass = REGISTRY.fetch(key) { abort "Unknown provider '#{key}'. Known: #{REGISTRY.keys.join(', ')}" }
      klass.new(key)
    end
  end

  class Runner
    CHECKS = %w[plain schema web_search web_fetch two_step combined].freeze

    def initialize(provider:, model:, checks:)
      @provider = provider
      @model = model
      @checks = checks
      @results = []
    end

    def run
      @checks.each { |check| record(check) { send("check_#{check}") } }
      report
    end

    private

    def record(check)
      started = Time.now
      outcome = yield
      @results << { check: check, status: outcome[:status], note: outcome[:note],
                    evidence: outcome[:evidence], seconds: (Time.now - started).round(1) }
    rescue StandardError => e
      @results << { check: check, status: "FAIL", note: "#{e.class}: #{e.message.to_s[0, 300]}",
                    evidence: nil, seconds: (Time.now - started).round(1) }
    end

    def check_plain
      text = ask { |chat| chat }
      pass(text.match?(/pong/i), "expected 'pong'", text) { "plain round trip" }
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
      pass(text.match?(%r{https?://}) && text.length > 80, "no URLs in response", text) { "web search grounding" }
    end

    def check_web_fetch
      params = @provider.web_fetch_params(@model)
      return { status: "SKIP", note: "provider declares no web-fetch mechanism", evidence: nil } if params.nil?

      chat = @provider.chat(@model).with_params(**params)
      text = chat.ask("Fetch https://example.com/ and quote the exact text of its <h1> heading.").content.to_s
      pass(text.match?(/example domain/i), "page content not quoted", text) { "web fetch grounding" }
    end

    # Production pipeline: Loader::LlmLoader#load.
    def check_two_step
      gather = @provider.chat(@model)
      @provider.prepare_web(gather)
      gather.with_params(**@provider.web_params(@model))
      gathered = gather.ask(GATHER_PROMPT).content.to_s
      return { status: "FAIL", note: "gather returned blank", evidence: nil } if gathered.strip.empty?

      structure = @provider.chat(@model).with_schema(PROBE_SCHEMA)
      validate_items(structure.ask(STRUCTURE_PROMPT_PREFIX + gathered), gathered: gathered)
    end

    # Expected to fail through RubyLLM (spec 005 §6) — recorded as evidence,
    # PASS here means "works combined", which would simplify the architecture.
    def check_combined
      chat = @provider.chat(@model).with_schema(PROBE_SCHEMA)
      @provider.prepare_web(chat)
      chat.with_params(**@provider.web_params(@model))
      validate_items(chat.ask(GATHER_PROMPT))
    end

    def ask
      chat = yield(@provider.chat(@model))
      chat.ask("Reply with the single word: pong").content.to_s
    end

    def validate_items(response, gathered: nil)
      raw = response.content
      payload = raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
      errors = JSONSchemer.schema(PROBE_SCHEMA).validate(payload).to_a
      items = payload.is_a?(Hash) ? Array(payload["items"]) : []
      evidence = { items: items.first(3), gathered_preview: gathered&.slice(0, 500) }.compact
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
      { status: condition ? "PASS" : "FAIL", note: condition ? yield : fail_note, evidence: evidence.to_s[0, 800] }
    end

    def report
      puts "\n#{@provider.key} / #{@model}"
      @results.each { |r| puts format("  %-11s %-4s %5ss  %s", r[:check], r[:status], r[:seconds], r[:note]) }
      path = write_transcript
      puts "\nTranscript: #{path}"
      @results.none? { |r| r[:status] == "FAIL" }
    end

    def write_transcript
      dir = File.expand_path("../tmp/llm_probe", __dir__)
      FileUtils.mkdir_p(dir)
      path = File.join(dir, "#{@provider.key}-#{@model.tr('/. ', '--_')}-#{Time.now.strftime('%Y%m%d-%H%M%S')}.json")
      File.write(path, JSON.pretty_generate(provider: @provider.key, model: @model, ran_at: Time.now.utc.iso8601,
                                            ruby_llm: RubyLLM::VERSION, results: @results))
      path
    end
  end
end

options = { checks: LlmCapabilityProbe::Runner::CHECKS }
OptionParser.new do |parser|
  parser.on("--provider KEY", "anthropic | moonshot") { |v| options[:provider] = v }
  parser.on("--model ID", "Model id as the provider names it") { |v| options[:model] = v }
  parser.on("--checks LIST", "Comma-separated subset of: #{LlmCapabilityProbe::Runner::CHECKS.join(',')}") do |v|
    options[:checks] = v.split(",").map(&:strip) & LlmCapabilityProbe::Runner::CHECKS
  end
end.parse!
abort "Required: --provider and --model" unless options[:provider] && options[:model]

provider = LlmCapabilityProbe::Provider.build(options[:provider])
exit LlmCapabilityProbe::Runner.new(provider: provider, model: options[:model], checks: options[:checks]).run ? 0 : 1
