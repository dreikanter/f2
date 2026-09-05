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
    # Extraction is one call where the provider can carry web + schema together
    # (Anthropic), and two otherwise — gather with web access, then structure
    # the gathered text under the schema. The adapter owns which (see
    # `#combined_extraction?`).
    def load
      client = options.fetch(:llm_client) { LlmClient.for(feed) }
      ctx = call_context(client)
      payload = extract(client, ctx)

      raise StandardError, "LlmLoader payload missing 'items' array" unless payload.is_a?(Hash) && payload["items"].is_a?(Array)

      payload["items"]
    rescue LlmClient::SchemaError => e
      # A reply that won't fit the schema is the source misbehaving, same as an
      # HTTP loader's bad status: an expected failure per the LlmClient
      # contract, already billed and recorded on the feed — not a crash. The
      # report keeps it visible as a handled error once it's wrapped, since
      # FeedRefreshJob deliberately swallows Loader::Error.
      Rails.error.report(e, context: { feed_id: feed.id, profile_key: feed.feed_profile_key })
      raise Loader::Error, e.message
    end

    private

    def extract(client, ctx)
      schema = config.fetch(:output_schema)
      if LlmClient::Adapter.for(client.credential.provider).combined_extraction?
        client.call(ctx, system: LlmPrompts::COMBINED_SYSTEM, prompt: rendered_prompt, output_schema: schema, web: true).payload
      else
        gathered = client.call(ctx, system: LlmPrompts::GATHER_SYSTEM, prompt: rendered_prompt, output_schema: nil, web: true).payload
        return empty_gather_result if gathered.blank?

        client.call(ctx, system: LlmPrompts::STRUCTURE_SYSTEM, prompt: structuring_prompt(gathered), output_schema: schema, web: false).payload
      end
    end

    # A blank/whitespace gather yields zero items and skips the structure call:
    # feeding emptiness (or a model refusal) into structuring invites fabricated
    # items, exactly what the grounding safeguard forbids. Recorded
    # so a persistently empty AI feed is visible to operators.
    def empty_gather_result
      feed.note_ai_gather_empty!
      { "items" => [] }
    end

    def call_context(client)
      LlmClient::CallContext.new(
        feed: feed.persisted? ? feed : nil,
        profile_key: feed.feed_profile_key,
        stage: :loader,
        model: model_for(client.credential),
        purpose: options.fetch(:purpose, :scheduled_run),
        search_credential: feed.search_credential,
        refresh_event: options[:refresh_event]
      )
    end

    # The structuring instructions live in LlmPrompts::STRUCTURE_SYSTEM; this
    # user message carries only the gathered text, framed as data.
    def structuring_prompt(gathered)
      <<~PROMPT
        Gathered web content:

        #{gathered}
      PROMPT
    end

    def model_for(credential)
      feed.effective_ai_model(credential).presence || credential.llm_provider.default_model
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
