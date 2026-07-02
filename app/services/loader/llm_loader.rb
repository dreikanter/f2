module Loader
  # LLM-backed loader. Asks `LlmClient` to extract a list of post-like
  # items from the source URL (or other input shape) using a profile-
  # provided prompt + output schema. Returns the structured payload
  # `{ "items" => [...] }` directly; PassthroughProcessor unpacks it
  # into FeedEntry instances downstream.
  #
  # The profile entry must declare `loader: { class: "Loader::LlmLoader",
  # config: { prompt_template:, output_schema: } }`. The model is
  # not part of the profile config: it comes from the feed's override or
  # the provider default (see `#model_for`).
  class LlmLoader < Base
    # Two calls, because structured output and web tools can't share one request:
    # first gather content with web access (no schema), then convert that text
    # into the structured items (schema, no web).
    def load
      client = options.fetch(:llm_client) { LlmClient.for(feed) }
      ctx = call_context(client)

      gathered = client.call(ctx, prompt: rendered_prompt, output_schema: nil, web: true).payload
      payload = client.call(ctx, prompt: structuring_prompt(gathered), output_schema: config.fetch(:output_schema), web: false).payload

      raise StandardError, "LlmLoader payload missing 'items' array" unless payload.is_a?(Hash) && payload["items"].is_a?(Array)

      items = payload["items"]
      limit = options[:limit]
      limit ? items.first(limit) : items
    end

    private

    def call_context(client)
      LlmClient::CallContext.new(
        feed: feed.persisted? ? feed : nil,
        profile_key: feed.feed_profile_key,
        stage: :loader,
        model: model_for(client.credential),
        purpose: options.fetch(:purpose, :scheduled_run)
      )
    end

    def structuring_prompt(gathered)
      <<~PROMPT
        Convert the gathered web content below into the required JSON object.
        Use only what is present; do not invent items or fields.

        GATHERED CONTENT:
        #{gathered}
      PROMPT
    end

    # Feed override wins; otherwise the resolved credential's provider default,
    # so the model always matches the provider actually being called.
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
