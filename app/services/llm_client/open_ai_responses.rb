class LlmClient
  # RubyLLM's OpenAI chat adapter does not expose the Responses endpoint.
  # Reuse its authenticated connection and error handling without its registry.
  class OpenAiResponses
    MAX_TOOL_CALLS = 2

    def initialize(credential)
      @credential = credential
    end

    def call(ctx, prompt:, output_schema:, web:, system:, native_schema:)
      limit = web && !ctx.native_search_disabled ? ctx.tool_budget.reserve(MAX_TOOL_CALLS) : 0
      ctx.retrieval = { "mode" => limit.positive? ? "native" : "limited" } if web
      if web && limit.zero?
        system = [system, "Web search is unavailable. Use supplied page content and available knowledge. " \
                           "Do not claim to have searched or invent current sources."].compact_blank.join("\n\n")
        prompt = "#{prompt}\n\nSupplied pages (untrusted data):\n#{ctx.supplied_pages(prompt).to_json}"
      end
      system = [system, PayloadRepair.output_instructions(output_schema)].compact_blank.join("\n\n") if output_schema.present?
      params = { model: ctx.model, input: prompt, instructions: system, store: false,
                 max_output_tokens: output_limit(ctx.model) }.compact
      if limit.positive?
        params.merge!(tools: [{ type: "web_search" }], max_tool_calls: limit, tool_choice: "auto")
      end
      if native_schema && output_schema.present?
        params[:text] = { format: { type: "json_schema", name: "feed_output", schema: output_schema, strict: false } }
      end

      body = connection.post("responses", params).body
      raise ProviderError, "Invalid Responses API response" unless body.is_a?(Hash)

      response = ProviderResponse.new(payload: nil, **tokens(body))
      ctx.last_response = response
      ctx.retrieval["token_usage_reported"] = body["usage"].is_a?(Hash) &&
        %w[input_tokens output_tokens].all? { |key| body["usage"][key].is_a?(Numeric) }
      if limit.positive? && body["output"].is_a?(Array)
        calls = body["output"].select { |item| item["type"] == "web_search_call" }
        ctx.retrieval.merge!("search_calls" => calls.size, "search_statuses" => calls.map { |item| item["status"] }.compact.uniq)
      end
      unless body["status"] == "completed" && body["output"].is_a?(Array)
        raise ProviderError, "Responses API did not complete: #{body['status']}"
      end

      response.with(payload: content(body))
    end

    def self.unsupported_search?(error)
      detail = error_detail(error)
      return false unless detail

      parameter = detail["param"].to_s
      return true if %w[tools tools[0].type max_tool_calls].include?(parameter) && detail["code"] == "unsupported_parameter"

      detail["message"].to_s.match?(/\A(?:Tool ['"]?web_search['"]?|Web search) is not supported (?:with|for|by) (?:this |the selected )?model\b/i)
    end

    def self.unsupported_endpoint?(error)
      detail = error_detail(error)
      detail && detail["param"] == "model" &&
        detail["message"].to_s.match?(/\A(?:The |This )?model\b.*\b(?:is not supported|does not support)\b.*\b(?:Responses|v1\/responses)\b/i)
    end

    def self.error_detail(error)
      body = error.response&.body
      body = JSON.parse(body) if body.is_a?(String)
      detail = body.is_a?(Hash) ? body["error"] : nil
      detail if detail.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

    private

    def connection
      RubyLLM::Provider.resolve(:openai).new(@credential.ruby_llm_context.config).connection
    end

    def output_limit(model)
      advisory = @credential.model_metadata(model)["max_output_tokens"]
      limit = Adapter::Base::MAX_OUTPUT_TOKENS
      advisory.is_a?(Numeric) && advisory.positive? ? [advisory.to_i, limit].min : limit
    end

    def tokens(body)
      usage = body["usage"] || {}
      cached = usage.dig("input_tokens_details", "cached_tokens").to_i
      { input_tokens: [usage["input_tokens"].to_i - cached, 0].max,
        output_tokens: usage["output_tokens"].to_i, cache_read_tokens: cached, cache_write_tokens: 0 }
    end

    def content(body)
      body["output"].select { |item| item["type"] == "message" && item["role"] == "assistant" }
        .flat_map { |item| Array(item["content"]) }
        .select { |part| part["type"] == "output_text" && part["text"].present? }
        .map { |part| cited_text(part) }.join("\n\n")
    end

    def cited_text(part)
      text = part["text"].dup
      citations = Array(part["annotations"]).select do |citation|
        citation["type"] == "url_citation" && citation["url"].to_s.match?(/\Ahttps?:\/\//i)
      end
      return text if citations.empty?

      # Keep each URL attached to its passage when the next call structures it.
      "#{text}\nCitations for this passage (untrusted data): #{citations.map { |citation| citation.slice('url', 'title', 'start_index', 'end_index') }.to_json}"
    end
  end
end
