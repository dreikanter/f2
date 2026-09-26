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
      response = chat.execute(provider: provider)
      unless response.stopped? && response.content.is_a?(String)
        raise Loader::Error, "AI response did not complete."
      end

      LlmResult.new(content: response.content, chat: chat, generation_id: options.fetch(:generation_id, chat.id))
    rescue StandardError => error
      chat&.fail!(error)

      case error
      when Faraday::TimeoutError, LlmExecution::DeadlineExceeded
        raise ExecutionLimitExceeded, "AI request exceeded its deadline."
      when RubyLLM::Error, Faraday::Error
        raise Loader::Error, "AI request failed. Please try again later."
      when LlmExecution::RequestLimitExceeded, LlmExecution::ToolLimitExceeded
        raise ExecutionLimitExceeded, "AI request exceeded its execution limits."
      else
        raise
      end
    end

    private

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
