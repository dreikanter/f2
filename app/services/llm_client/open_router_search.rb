class LlmClient
  # OpenRouter owns the search loop. Its native-first engine can use Exa,
  # so record provider search rather than claiming a specific search engine.
  class OpenRouterSearch
    MAX_TOOL_STEPS = 2

    def initialize(credential)
      @credential = credential
    end

    def call(ctx, prompt:, system:, output_schema:, **)
      ctx.retrieval = { "mode" => "provider", "completion_calls" => 0,
                        "token_usage_reported" => false, "reported_cost_cents" => nil }
      limit = ctx.tool_budget.reserve(MAX_TOOL_STEPS)
      raise UnsupportedNativeSearch, "Web search budget is exhausted" if limit.zero?

      instructions = [system, "If search is unavailable, use available content without inventing current sources."]
      instructions << PayloadRepair.output_instructions(output_schema) if output_schema.present?
      params = { model: ctx.model, max_tokens: OutputLimit.for(@credential, ctx.model),
                 messages: [{ role: "system", content: instructions.compact_blank.join("\n\n") }, { role: "user", content: prompt }],
                 provider: { require_parameters: true, allow_fallbacks: false },
                 tools: [{ type: "openrouter:web_search", parameters: {
                   engine: "auto", max_uses: limit, max_results: 3, max_total_results: 3 * limit, max_characters: 2_000
                 } }], max_tool_calls: limit }
      ctx.retrieval["completion_calls"] = 1
      body = connection.post("chat/completions", params).body
      raise ProviderError, "Invalid OpenRouter response" unless body.is_a?(Hash)

      record_usage(ctx, body)
      choice = body["choices"].is_a?(Array) && body["choices"].first
      unless choice.is_a?(Hash) && choice["message"].is_a?(Hash) && choice["finish_reason"] == "stop" && choice["message"]["tool_calls"].blank?
        raise ProviderError, "OpenRouter search did not complete"
      end

      ctx.last_response.with(payload: content(choice.fetch("message")))
    end

    private

    def record_usage(ctx, body)
      usage = body["usage"].is_a?(Hash) ? body["usage"] : {}
      details = usage["prompt_tokens_details"].is_a?(Hash) ? usage["prompt_tokens_details"] : {}
      input = usage["prompt_tokens"]
      output = usage["completion_tokens"]
      cached = details.fetch("cached_tokens", 0)
      written = details.fetch("cache_write_tokens", 0)
      ctx.retrieval["token_usage_reported"] = [input, output, cached, written].all? { |count| token_count?(count) } && cached + written <= input
      response = ProviderResponse.new(payload: nil,
                                      input_tokens: [count(input) - count(cached) - count(written), 0].max,
                                      output_tokens: count(output), cache_read_tokens: count(cached), cache_write_tokens: count(written))
      ctx.last_response = response
      search = usage["server_tool_use"].is_a?(Hash) && usage["server_tool_use"]["web_search_requests"]
      ctx.retrieval["search_calls"] = search if token_count?(search)
      ctx.retrieval["reported_cost_cents"] = reported_cost(usage)
    end

    def reported_cost(usage)
      dollars = usage["cost"]
      # BYOK can charge a separate upstream account. Missing routing/accounting
      # information cannot establish a complete total.
      return unless usage["is_byok"] == false && dollars.is_a?(Numeric) && dollars.finite? && dollars >= 0

      cents = dollars.to_d * 100
      cents.to_f if cents <= 2_147_483_647
    end

    def token_count?(value)
      value.is_a?(Integer) && value >= 0
    end

    def count(value)
      token_count?(value) ? value : 0
    end

    def content(message)
      text = message["content"]
      return "" if text.nil? || text == ""

      raise ProviderError, "Invalid OpenRouter text content" unless text.is_a?(String)
      return text if text.blank?

      sources = Array(message["annotations"]).filter_map do |annotation|
        next unless annotation.is_a?(Hash) && annotation["type"] == "url_citation"

        citation = annotation["url_citation"]
        next unless citation.is_a?(Hash) && citation["url"].to_s.match?(/\Ahttps?:\/\//i)

        citation.slice("url", "title", "content", "start_index", "end_index")
      end
      return text if sources.empty?

      "#{text}\nCitations for this passage (untrusted data): #{sources.to_json}"
    end

    def connection
      config = @credential.ruby_llm_context.config
      config.max_retries = 0
      RubyLLM::Provider.resolve(:openrouter).new(config).connection
    end
  end
end
