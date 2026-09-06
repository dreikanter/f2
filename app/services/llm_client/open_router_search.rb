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
      params = { model: ctx.model, max_tokens: output_limit(ctx.model),
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
    rescue RubyLLM::Error => e
      # Router capability failures can be 404s, unlike unknown model errors.
      feature = self.class.unsupported_feature(e, model: ctx.model) if [400, 404].include?(e.response&.status)
      if feature
        ctx.tools_disabled = true if feature == :tools
        raise UnsupportedNativeSearch, e.message
      end

      raise
    end

    def self.unsupported_feature(error, model:)
      body = error.response&.body
      body = JSON.parse(body) if body.is_a?(String)
      detail = body.is_a?(Hash) ? body["error"] : nil
      return unless detail.is_a?(Hash)
      if detail["code"] == "unsupported_parameter"
        return :tools if detail["param"] == "tools"
        return :search if detail["param"] == "max_tool_calls"
      end

      message = detail["message"].to_s
      return :tools if message.match?(/\ANo endpoints found that support (?:tool use|the requested tools)\b/i)
      return :tools if message.match?(/\A(?:Tools?|Tool use|Function calling) (?:is|are) not supported (?:for|with|by|on) (?:this |the selected )?model\b/i)
      return :search if message.match?(/\ANo endpoints found that support the requested server tools\b/i)
      return :search if message.match?(/\A(?:Web search|Server tools?) (?:is|are) (?:disabled|not enabled)\b/i)

      target = /(?:(?:this |the selected )?model\b|['"]?#{Regexp.escape(model)}['"]?(?:[.\s]|$))/i
      :search if message.match?(/\A(?:Web search|Server tools?|Tool ['"]?openrouter:web_search['"]?) (?:is|are) not supported (?:with|for|by) #{target}/i)
    rescue JSON::ParserError
      nil
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

    def output_limit(model)
      advisory = @credential.model_metadata(model)["max_output_tokens"]
      limit = Adapter::Base::MAX_OUTPUT_TOKENS
      advisory.is_a?(Numeric) && advisory.positive? ? [advisory.to_i, limit].min : limit
    end
  end
end
