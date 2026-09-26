module Loader
  # AI extraction entry point for the shared feed pipeline.
  class LlmLoader < Base
    class ExecutionLimitExceeded < Loader::Error; end

    # @return [LlmResult] response content with its guarded extraction lifecycle
    def load
      raise Loader::Error, "An active AI credential is required." unless feed.ai_credential&.active?
      raise Loader::Error, "An AI model is required." if feed.ai_model.blank?
      raise Loader::Error, "External search is not supported yet." if feed.search_credential_id.present?

      provider = feed.ai_credential.build_llm_provider
      chat = create_chat(provider)
      prepare_chat(chat)
      limits = options.fetch(:execution_limits, {})
      initial_limits = x_today_request? ? limits.merge(max_requests: 1) : limits
      response = chat.execute(provider: provider, execution_limits: initial_limits)
      response = x_search_retry(chat, provider, response) if empty_x_today_response?(response)
      unless response.stopped? && response.content.is_a?(String)
        raise Loader::Error, "AI response did not complete."
      end

      LlmResult.new(content: response.content, chat: chat)
    rescue StandardError => error
      chat&.fail!(error)

      case error
      when Faraday::TimeoutError, LlmExecution::DeadlineExceeded
        raise ExecutionLimitExceeded, "AI request exceeded its deadline."
      when RubyLLM::Error, Faraday::Error
        raise Loader::Error, "AI request failed. Please try again later."
      when LlmExecution::RequestLimitExceeded, LlmExecution::ToolLimitExceeded, LlmExecution::TokenLimitExceeded
        raise ExecutionLimitExceeded, "AI request exceeded its execution limits."
      else
        raise
      end
    end

    private

    def x_today_request?
      input = feed.source_input
      input.match?(/\bx\.com\b/i) && input.match?(/\btoday\b/i) &&
        !input.match?(%r{\b(?:time\s*zone|[A-Za-z_]+/[A-Za-z_]+|(?:UTC|GMT)[+-]\d+|Pacific|Eastern|Central|Mountain|CET|CEST|PST|PDT|EST|EDT|BST|JST)\b}i)
    end

    def empty_x_today_response?(response)
      x_today_request? && options.fetch(:execution_limits, {}).fetch(:max_requests, LlmExecution::MAX_REQUESTS) > 1 &&
        JSON.parse(response.content)["items"] == []
    rescue JSON::ParserError, TypeError
      false
    end

    def x_search_retry(chat, provider, response)
      candidates = XSearchFallback.new(chat).candidates
      return response if candidates.empty?

      chat.with_provider_tools(nil)
      chat.ask_later(<<~TEXT)
        The first search returned no items. Public X pages linked from its native search
        results show these posts published today UTC. Select the strongest one that
        satisfies the original feed request. Use only the verified text and permalink
        below. published_at is source metadata; retrieved_at is the time this
        application fetched the page. Do not invent missing details. Return
        {"items":[]} if none qualifies.

        #{JSON.pretty_generate(candidates)}
      TEXT
      result = chat.execute(provider: provider, execution_limits: fallback_execution_limits(chat))
      source_urls = candidates.pluck(:source_url)
      items = JSON.parse(result.content).fetch("items")
      raise Loader::Error, "AI selected an unverified X post." unless
        items.is_a?(Array) && items.all? { |item| item.is_a?(Hash) && source_urls.include?(item["source_url"]) }

      result
    rescue JSON::ParserError, KeyError
      raise Loader::Error, "AI returned invalid X fallback output."
    end

    def fallback_execution_limits(chat)
      limits = options.fetch(:execution_limits, {}).merge(max_requests: 1, max_tool_calls: 1)
      return limits unless limits[:max_total_tokens]

      usages = chat.ruby_llm_usages
      raise LlmExecution::TokenLimitExceeded if usages.any? { |usage| usage.input_tokens.nil? || usage.output_tokens.nil? }

      spent = usages.sum { |usage| usage.input_tokens + usage.output_tokens }
      remaining = limits[:max_total_tokens] - spent
      raise LlmExecution::TokenLimitExceeded unless remaining.positive?

      limits.merge(max_total_tokens: remaining)
    end

    def create_chat(provider)
      # Another worker may have refreshed the persisted catalog.
      if RubyLLM::ActiveRecord::Model.exists?
        RubyLLM.models.load_from_store
      else
        RubyLLM.models.load_from_json
      end

      now = Time.current
      LlmChat.create!(
        user: feed.user,
        feed: options.fetch(:usage_feed, feed.persisted? ? feed : nil),
        ai_credential: feed.ai_credential,
        requested_provider: feed.ai_credential.provider,
        requested_model: feed.ai_model,
        profile_key: feed.feed_profile_key,
        purpose: options.fetch(:purpose, :scheduled_run),
        started_at: now,
        deadline_at: options.fetch(:deadline_at, now + LlmChat::TIMEOUT),
        model: feed.ai_model,
        provider: feed.ai_credential.provider,
        context: provider.context,
        protocol: provider.protocol,
        assume_model_exists: true
      )
    end

    def prepare_chat(chat)
      options[:refresh_event]&.event_references&.create!(reference: chat)
      output = LlmOutput.new(feed)
      chat.with_instructions(LlmPrompts.extraction_system(started_at: chat.started_at, max_items: output.max_items))
      chat.with_thinking(effort: options[:thinking_effort]) if options[:thinking_effort]
      chat.with_schema(output_schema(output))
      chat.with_provider_tools(:web_search)
      chat.ask_later(config.fetch(:prompt_template).gsub("{{input}}") { feed.source_input })
    end

    # Strict output requires every property; the processor accepts this subset.
    def output_schema(output)
      schema = output.schema
      item = schema.fetch("properties").fetch("items").fetch("items")
      item.fetch("properties").delete("uid")
      item["required"] = item.fetch("properties").keys
      schema
    end

    def config
      FeedProfile.config_for(feed.feed_profile_key, :loader)
    end
  end
end
