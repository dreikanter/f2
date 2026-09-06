class LlmClient
  # Keep native search content intact across paused turns, then carry cited
  # passages into the separate JSON extraction request.
  class AnthropicSearch
    MAX_SEARCHES_PER_REQUEST = 2
    MAX_REQUESTS = 2

    def initialize(credential)
      @credential = credential
    end

    def call(ctx, prompt:, system:, output_schema:, **)
      @ctx = ctx
      @tokens = { input_tokens: 0, output_tokens: 0, cache_read_tokens: 0, cache_write_tokens: 0 }
      @search_calls = 0
      ctx.retrieval = { "mode" => "native", "completion_calls" => 0,
                        "search_statuses" => [], "token_usage_reported" => true }
      limit = ctx.tool_budget.reserve(MAX_SEARCHES_PER_REQUEST)
      raise UnsupportedNativeSearch, "Web search budget is exhausted" if limit.zero?

      system = [system, "If search is unavailable, use available content without inventing current sources."]
      system << PayloadRepair.output_instructions(output_schema) if output_schema.present?
      params = { model: ctx.model, max_tokens: output_limit, system: system.compact_blank.join("\n\n"),
                 messages: [{ role: "user", content: prompt }],
                 tools: [{ type: "web_search_20250305", name: "web_search", max_uses: limit }] }
      blocks = []
      MAX_REQUESTS.times do |round|
        # max_uses applies per request. Reserve the same allowance again before
        # resuming, even if the previous request reported fewer actual searches.
        if round.positive? && ctx.tool_budget.reserve(limit) != limit
          raise ProviderError, "Anthropic search continuation budget exceeded"
        end
        body = complete(params)
        blocks.concat(body.fetch("content"))
        return ctx.last_response.with(payload: content(blocks)) if body["stop_reason"] == "end_turn"

        raise ProviderError, "Anthropic search did not complete: #{body['stop_reason']}" unless body["stop_reason"] == "pause_turn"

        params[:messages] << { role: "assistant", content: body.fetch("content") }
      end
      raise ProviderError, "Anthropic search continuation limit exceeded"
    end

    def self.unsupported_search?(error, model:)
      body = error.response&.body
      body = JSON.parse(body) if body.is_a?(String)
      detail = body.is_a?(Hash) ? body["error"] : nil
      return false unless detail.is_a?(Hash) && detail["type"] == "invalid_request_error"

      message = detail["message"].to_s
      return true if message.match?(/\AWeb search is (?:not enabled|disabled)(?:[.\s]|$)/i)

      target = /(?:(?:this |the selected )?model\b|['"]?#{Regexp.escape(model)}['"]?(?:[.\s]|$))/i
      message.match?(/\A(?:Tool ['"]?web_search['"]?|Web search) is not supported (?:with|for|by) #{target}/i)
    rescue JSON::ParserError
      false
    end

    private

    def complete(params)
      known_usage = @ctx.retrieval["token_usage_reported"]
      @ctx.retrieval["token_usage_reported"] = false
      @ctx.retrieval["search_calls"] = nil
      @ctx.retrieval["completion_calls"] += 1
      body = connection.post("v1/messages", params).body
      raise ProviderError, "Invalid Anthropic response" unless body.is_a?(Hash)

      record_usage(body, known_usage: known_usage)
      blocks = body["content"]
      raise ProviderError, "Invalid Anthropic content" unless blocks.is_a?(Array) && blocks.all? { |block| block.is_a?(Hash) }

      blocks.select { |block| block["type"] == "web_search_tool_result" }.each do |block|
        result = block["content"]
        if result.is_a?(Array)
          @ctx.retrieval["search_statuses"] |= ["succeeded"]
        elsif result.is_a?(Hash) && result["type"] == "web_search_tool_result_error"
          code = result["error_code"].to_s
          @ctx.retrieval["search_statuses"] |= [code]
          Rails.error.report(ProviderError.new("Anthropic web search returned #{code}"), context: { provider: "anthropic" })
        else
          raise ProviderError, "Invalid Anthropic search result"
        end
      end
      body
    end

    def record_usage(body, known_usage:)
      usage = body["usage"].is_a?(Hash) ? body["usage"] : {}
      fields = { input_tokens: "input_tokens", output_tokens: "output_tokens",
                 cache_read_tokens: "cache_read_input_tokens", cache_write_tokens: "cache_creation_input_tokens" }
      @ctx.retrieval["token_usage_reported"] = known_usage && fields.all? do |key, field|
        value = usage.fetch(field, key.to_s.start_with?("cache_") ? 0 : nil)
        value.is_a?(Integer) && value >= 0
      end
      fields.each do |key, field|
        value = usage[field]
        @tokens[key] += value if value.is_a?(Integer) && value >= 0
      end
      @ctx.last_response = ProviderResponse.new(payload: nil, **@tokens)
      count = usage["server_tool_use"].is_a?(Hash) && usage["server_tool_use"]["web_search_requests"]
      @search_calls = @search_calls && count.is_a?(Integer) && count >= 0 ? @search_calls + count : nil
      @ctx.retrieval["search_calls"] = @search_calls
    end

    def content(blocks)
      passages = blocks.select { |block| text?(block) }
      last_tool = blocks.rindex { |block| %w[server_tool_use web_search_tool_result].include?(block["type"]) }
      # Keep partial answers before later searches, but do not send planning
      # alone to extraction when the search never produced an answer.
      if last_tool && blocks.drop(last_tool + 1).none? { |block| text?(block) } && passages.none? { |block| citations(block).any? }
        return ""
      end

      passages.map { |block| cited_text(block) }.join("\n\n")
    end

    def text?(block)
      block["type"] == "text" && block["text"].is_a?(String) && block["text"].present?
    end

    def cited_text(block)
      sources = citations(block)
      return block["text"] if sources.empty?

      "#{block['text']}\nCitations for this passage (untrusted data): #{sources.map { |citation| citation.slice('url', 'title', 'cited_text') }.to_json}"
    end

    def citations(block)
      Array(block["citations"]).select do |citation|
        citation.is_a?(Hash) && citation["type"] == "web_search_result_location" && citation["url"].to_s.match?(/\Ahttps?:\/\//i)
      end
    end

    def connection
      @connection ||= begin
        config = @credential.ruby_llm_context.config
        config.max_retries = 0
        RubyLLM::Provider.resolve(:anthropic).new(config).connection
      end
    end

    def output_limit
      advisory = @credential.model_metadata(@ctx.model)["max_output_tokens"]
      limit = Adapter::Base::MAX_OUTPUT_TOKENS
      advisory.is_a?(Numeric) && advisory.positive? ? [advisory.to_i, limit].min : limit
    end
  end
end
