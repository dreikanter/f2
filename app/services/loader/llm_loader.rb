module Loader
  # LLM-backed loader. Asks `LlmClient` to extract a list of post-like
  # items from the source URL (or other input shape) using a profile-
  # provided prompt + output schema. Returns the structured payload
  # `{ "items" => [...] }` directly; PassthroughProcessor unpacks it
  # into FeedEntry instances downstream.
  #
  # The profile entry must declare `loader: { class: "Loader::LlmLoader",
  # config: { prompt_template:, output_schema:, tools? } }`. The model is
  # not part of the profile config: it comes from the feed's override or
  # the provider default (see `#model_for`).
  class LlmLoader < Base
    def load
      llm_client = options.fetch(:llm_client) { LlmClient.for(feed) }
      ctx = LlmClient::CallContext.new(
        feed: feed.persisted? ? feed : nil,
        profile_key: feed.feed_profile_key,
        stage: :loader,
        model: model_for(llm_client.credential),
        purpose: options.fetch(:purpose, :scheduled_run)
      )
      result = llm_client.call(ctx,
                               prompt: rendered_prompt,
                               output_schema: config.fetch(:output_schema),
                               tools: config.fetch(:tools, []))

      payload = result.payload
      raise StandardError, "LlmLoader payload missing 'items' array" unless payload.is_a?(Hash) && payload["items"].is_a?(Array)

      limit = options[:limit]
      limit ? payload["items"].first(limit) : payload["items"]
    end

    private

    # The feed's explicit model override wins; otherwise fall back to the
    # default model of whichever provider the resolved credential belongs
    # to, so the model always matches the provider actually being called.
    def model_for(credential)
      feed.ai_model.presence || LlmProvider.find(credential.provider).default_model
    end

    def config
      @config ||= FeedProfile.config_for(feed.feed_profile_key, :loader).symbolize_keys
    end

    def rendered_prompt
      source = feed.source_input.to_s
      config.fetch(:prompt_template).to_s.gsub("{{input}}") { source }
    end
  end
end
