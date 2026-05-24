module Loader
  # LLM-backed loader. Asks `LlmClient` to extract a list of post-like
  # items from the source URL (or other input shape) using a profile-
  # provided prompt + output schema. Returns the structured payload
  # `{ "items" => [...] }` directly; PassthroughProcessor unpacks it
  # into FeedEntry instances downstream.
  #
  # The profile entry must declare `loader: { class: "Loader::LlmLoader",
  # config: { model:, prompt_template:, output_schema:, tools? } }`.
  class LlmLoader < Base
    def load
      llm_client = options.fetch(:llm_client) { LlmClient.for(feed) }
      result = llm_client.call(
        feed: feed.persisted? ? feed : nil,
        profile_key: feed.feed_profile_key,
        stage: :loader,
        purpose: options.fetch(:purpose, :scheduled_run),
        model: config.fetch(:model),
        prompt: rendered_prompt,
        output_schema: config.fetch(:output_schema),
        tools: config.fetch(:tools, [])
      )

      payload = result.payload
      raise StandardError, "LlmLoader payload missing 'items' array" unless payload.is_a?(Hash) && payload["items"].is_a?(Array)

      limit = options[:limit]
      limit ? payload["items"].first(limit) : payload["items"]
    end

    private

    def config
      @config ||= FeedProfile.config_for(feed.feed_profile_key, :loader).symbolize_keys
    end

    def rendered_prompt
      source = feed.source_input.to_s
      config.fetch(:prompt_template).to_s
            .gsub("{{url}}", source)
            .gsub("{{input}}", source)
            .gsub("{{#{feed.source_input_shape}}}", source)
    end
  end
end
