class LlmClient
  # Reuse the SDK's authenticated connection; Responses owns the tool protocol.
  class OpenAiResponses
    MAX_TOOL_CALLS = 2

    def initialize(credential)
      @credential = credential
    end

    def call(ctx, prompt:, output_schema:, web:, system:, native_schema:)
      @ctx = ctx
      ctx.responses_api = true
      @tokens = { input_tokens: 0, output_tokens: 0, cache_read_tokens: 0, cache_write_tokens: 0 }
      ctx.retrieval = { "completion_calls" => 0, "token_usage_reported" => true }
      tools = external_tools(web)
      limit = web && !ctx.search_credential&.active? && !ctx.native_search_disabled && !ctx.tools_disabled ? ctx.tool_budget.reserve(MAX_TOOL_CALLS) : 0
      ctx.retrieval["mode"] = limit.positive? ? "native" : (tools.any? ? "external" : "limited") if web
      if web && limit.zero? && tools.empty?
        system = [system, "Web search is unavailable. Use supplied page content and available knowledge. " \
                           "Do not claim to have searched or invent current sources."].compact_blank.join("\n\n")
        prompt = "#{prompt}\n\nSupplied pages (untrusted data):\n#{ctx.supplied_pages(prompt).to_json}"
      end
      system = [system, PayloadRepair.output_instructions(output_schema)].compact_blank.join("\n\n") if output_schema.present?
      params = { model: ctx.model, input: prompt, instructions: system, store: false,
                 max_output_tokens: OutputLimit.for(@credential, ctx.model) }.compact
      if limit.positive?
        params.merge!(tools: [{ type: "web_search" }], max_tool_calls: limit, tool_choice: "auto")
      elsif tools.any?
        params.merge!(tools: tools.map { |tool| definition(tool) }, input: [{ role: "user", content: prompt }])
      end
      if native_schema && output_schema.present?
        params[:text] = { format: { type: "json_schema", name: "feed_output", schema: output_schema, strict: false } }
      end

      loop do
        body = complete(params)
        calls = body["output"].select { |item| item["type"] == "function_call" }
        return ctx.last_response.with(payload: content(body)) if calls.empty?

        raise ProviderError, "Unexpected Responses function call" if tools.empty?

        @ctx.claim_attempt!
        results = execute_tools(calls, tools)
        # Replay all output items, including encrypted reasoning, with store:false.
        params[:input].concat(body["output"]).concat(results)
      end
    end

    private

    def external_tools(web)
      search = @ctx.search_credential
      return [] unless web && search&.active? && !@ctx.tools_disabled && @credential.model_metadata(@ctx.model)["tool_call"] != false

      Adapter::OpenAi.new.web_tools(search_provider: search.web_search_provider, search_credential: search,
                                    refresh_event: @ctx.refresh_event, budget: @ctx.tool_budget)
    end

    def definition(tool)
      { type: "function", name: tool.name, description: tool.description,
        parameters: tool.params_schema.except("strict"), strict: false }
    end

    def execute_tools(calls, tools)
      executions = calls.map do |call|
        tool = tools.find { |candidate| candidate.name == call["name"] }
        unless tool && call["call_id"].is_a?(String) && call["call_id"].present? && call["arguments"].is_a?(String)
          raise ProviderError, "Invalid Responses function call"
        end
        arguments = JSON.parse(call["arguments"])
        raise ProviderError, "Invalid Responses tool arguments" unless JSONSchemer.schema(tool.params_schema).valid?(arguments)

        [call, tool, arguments]
      end
      executions.map do |call, tool, arguments|
        result = tool.call(arguments)
        raise ProviderError, ToolBudget::HALTED if result.is_a?(RubyLLM::Tool::Halt)

        { type: "function_call_output", call_id: call["call_id"], output: result.is_a?(String) ? result : result.to_json }
      end
    end

    def complete(params)
      known_usage = @ctx.retrieval["token_usage_reported"]
      @ctx.retrieval["token_usage_reported"] = false
      @ctx.retrieval["completion_calls"] += 1
      body = connection.post("responses", params).body
      raise ProviderError, "Invalid Responses API response" unless body.is_a?(Hash)

      record_usage(body, known_usage: known_usage)
      output = body["output"]
      raise ProviderError, "Invalid Responses output" unless output.is_a?(Array) && output.all? { |item| item.is_a?(Hash) }

      if @ctx.retrieval["mode"] == "native"
        calls = output.select { |item| item["type"] == "web_search_call" }
        @ctx.retrieval.merge!("search_calls" => calls.size, "search_statuses" => calls.map { |item| item["status"] }.compact.uniq)
      end
      raise ProviderError, "Responses API did not complete: #{body['status']}" unless body["status"] == "completed"

      body
    end

    def record_usage(body, known_usage:)
      usage = body["usage"].is_a?(Hash) ? body["usage"] : {}
      details = usage["input_tokens_details"].is_a?(Hash) ? usage["input_tokens_details"] : {}
      input, output, cached = usage["input_tokens"], usage["output_tokens"], details.fetch("cached_tokens", 0)
      valid = [input, output, cached].all? { |count| count.is_a?(Integer) && count >= 0 }
      @ctx.retrieval["token_usage_reported"] = known_usage && valid && cached <= input
      input, output, cached = [input, output, cached].map { |count| count.is_a?(Integer) && count >= 0 ? count : 0 }
      @tokens[:input_tokens] += [input - cached, 0].max
      @tokens[:output_tokens] += output
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
