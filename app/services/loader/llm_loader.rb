module Loader
  # AI extraction entry point for the shared feed pipeline.
  class LlmLoader < Base
    UNAVAILABLE_MESSAGE = "AI feeds are temporarily unavailable.".freeze

    attr_reader :chat

    def load
      raise Loader::Error, UNAVAILABLE_MESSAGE if feed.search_credential
      raise Loader::Error, "An active AI credential is required." unless feed.ai_credential&.active?
      raise Loader::Error, "An AI model is required." if feed.ai_model.blank?

      provider = feed.ai_credential.build_llm_client
      @chat = prepare_chat(provider)
      response = chat.execute(provider: provider)
      unless response.stopped? && response.content.is_a?(String)
        raise Loader::Error, "AI response did not complete."
      end

      response.content
    rescue RubyLLM::Error, Faraday::Error => error
      raise Loader::Error, "AI request failed: #{error.class.name}."
    rescue LlmExecution::DeadlineExceeded
      raise Loader::Error, "AI request exceeded its deadline."
    rescue LlmExecution::RequestLimitExceeded, LlmExecution::ToolLimitExceeded
      raise Loader::Error, "AI request exceeded its execution limits."
    end

    private

    def prepare_chat(provider)
      now = Time.current
      record = LlmChat.create!(
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
      record.with_instructions(<<~TEXT.strip)
        #{LlmPrompts::COMBINED_SYSTEM}

        Include every field in the output schema. Use empty strings or arrays
        for absent optional values; source_url may be null.
      TEXT
      record.with_schema(output_schema)
      record.with_server_tools(:web_search)
      record.ask_later(config.fetch(:prompt_template).gsub("{{input}}") { feed.source_input })
      record
    end

    # Strict output requires every property; the processor accepts this subset.
    def output_schema
      schema = config.fetch(:output_schema).deep_dup
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
