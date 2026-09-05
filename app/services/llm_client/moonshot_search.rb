class LlmClient
  # Formula search uses the same Moonshot credential and returns opaque content
  # for Kimi to read. Keep the assistant's reasoning intact between tool rounds.
  class MoonshotSearch
    FORMULA_PATH = "formulas/moonshot/web-search:latest".freeze
    MAX_SEARCH_CALLS = 2
    UNAVAILABLE = "Web search is unavailable. Use available content without inventing current sources.".freeze

    def initialize(credential)
      @credential = credential
    end

    def call(ctx, prompt:, system:, output_schema:, **)
      @ctx = ctx
      @tokens = { input_tokens: 0, output_tokens: 0, cache_read_tokens: 0, cache_write_tokens: 0 }
      ctx.retrieval = { "mode" => "native", "search_calls" => 0, "completion_calls" => 0,
                        "search_statuses" => [], "token_usage_reported" => true }
      tool = search_definition
      instructions = [system, "Use at most two searches, then answer from the evidence available."]
      instructions << PayloadRepair.output_instructions(output_schema) if output_schema.present?
      messages = [{ role: "system", content: instructions.compact_blank.join("\n\n") },
                  { role: "user", content: prompt }]
      choice = complete(messages, tool: tool)
      calls = tool_calls(choice)
      if calls.any?
        messages << choice.fetch("message").slice("role", "content", "tool_calls", "reasoning_content")
        calls.each do |call|
          messages << { role: "tool", tool_call_id: call.fetch("id"), content: search(call) }
        end
        choice = complete(messages, tool: tool, final: true)
      end
      # A provider ignoring tool_choice must not start another paid tool round.
      content = tool_calls(choice).empty? ? choice.dig("message", "content").to_s : ""
      ctx.last_response.with(payload: content)
    end

    private

    def search_definition
      body = connection.get("#{FORMULA_PATH}/tools").body
      tools = body.is_a?(Hash) && body["tools"]
      raise ProviderError, "Invalid Moonshot search tool declaration" unless tools.is_a?(Array)

      tool = tools.find do |item|
        item.is_a?(Hash) && item["type"] == "function" && item["function"].is_a?(Hash) && item["function"]["name"] == "web_search"
      end
      raise UnsupportedNativeSearch, "Moonshot web search is unavailable" unless tool
      raise ProviderError, "Invalid Moonshot search parameters" unless tool.dig("function", "parameters").is_a?(Hash)

      tool
    rescue RubyLLM::Error => e
      raise UnsupportedNativeSearch, "Moonshot search endpoint is unavailable" if [404, 501].include?(e.response&.status)

      raise
    end

    def complete(messages, tool:, final: false)
      known_usage = @ctx.retrieval["token_usage_reported"]
      @ctx.retrieval["token_usage_reported"] = false
      @ctx.retrieval["completion_calls"] += 1
      params = { model: @ctx.model, messages: messages, tools: [tool],
                 tool_choice: final ? "none" : "auto", max_tokens: output_limit }
      body = connection.post("chat/completions", params).body
      raise ProviderError, "Invalid Moonshot response" unless body.is_a?(Hash)

      record_tokens(body, known_usage: known_usage)
      choice = body["choices"].is_a?(Array) && body["choices"].first
      unless choice.is_a?(Hash) && choice["message"].is_a?(Hash) && %w[stop tool_calls].include?(choice["finish_reason"])
        raise ProviderError, "Moonshot response did not complete"
      end

      choice
    end

    def tool_calls(choice)
      calls = choice.dig("message", "tool_calls") || []
      unless calls.is_a?(Array) && calls.all? { |call| call.is_a?(Hash) && call["id"].is_a?(String) && call["id"].present? }
        raise ProviderError, "Invalid Moonshot tool calls"
      end
      raise ProviderError, "Duplicate Moonshot tool call IDs" unless calls.pluck("id").uniq.size == calls.size

      calls
    end

    def search(call)
      function = call["function"]
      unless call["type"] == "function" && function.is_a?(Hash) && function["name"] == "web_search"
        return { error: "Only the declared web search tool is available." }.to_json
      end
      arguments = function["arguments"]
      raise ProviderError, "Invalid Moonshot search arguments" unless arguments.is_a?(String) && JSON.parse(arguments).is_a?(Hash)
      if @ctx.retrieval["search_calls"] >= MAX_SEARCH_CALLS || @ctx.tool_budget.reserve(1).zero?
        return { error: ToolBudget::OVER_BUDGET }.to_json
      end

      # Record before sending: a timeout can still leave a billable search.
      @ctx.retrieval["search_calls"] += 1
      body = connection.post("#{FORMULA_PATH}/fibers", function.slice("name", "arguments")).body
      status = body.is_a?(Hash) ? body["status"].to_s : "invalid"
      @ctx.retrieval["search_statuses"] |= [status]
      result = body.dig("context", "output").presence || body.dig("context", "encrypted_output") if body.is_a?(Hash) && body["context"].is_a?(Hash)
      return result if status == "succeeded" && result.is_a?(String) && result.present?

      Rails.error.report(ProviderError.new("Moonshot search returned #{status}"), context: { provider: "moonshot" })
      { error: UNAVAILABLE }.to_json
    rescue RubyLLM::Error => e
      @ctx.retrieval["search_statuses"] |= ["failed"]
      raise unless [404, 501].include?(e.response&.status)

      Rails.error.report(e, context: { provider: "moonshot" })
      { error: UNAVAILABLE }.to_json
    end

    def record_tokens(body, known_usage:)
      usage = body["usage"].is_a?(Hash) ? body["usage"] : {}
      @ctx.retrieval["token_usage_reported"] = known_usage &&
        %w[prompt_tokens completion_tokens].all? { |key| usage[key].is_a?(Numeric) }
      cached = (usage.dig("prompt_tokens_details", "cached_tokens") || usage["cached_tokens"]).to_i
      @tokens[:input_tokens] += [usage["prompt_tokens"].to_i - cached, 0].max
      @tokens[:output_tokens] += usage["completion_tokens"].to_i
      @tokens[:cache_read_tokens] += cached
      @ctx.last_response = ProviderResponse.new(payload: nil, **@tokens)
    end

    def connection
      @connection ||= begin
        config = @credential.ruby_llm_context.config
        config.max_retries = 0
        RubyLLM::Provider.resolve(:openai).new(config).connection
      end
    end

    def output_limit
      advisory = @credential.model_metadata(@ctx.model)["max_output_tokens"]
      limit = Adapter::Base::MAX_OUTPUT_TOKENS
      advisory.is_a?(Numeric) && advisory.positive? ? [advisory.to_i, limit].min : limit
    end
  end
end
