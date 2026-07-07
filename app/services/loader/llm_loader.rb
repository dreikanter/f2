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

      items = payload["items"]
      limit = options[:limit]
      limit ? items.first(limit) : items
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
    # items, exactly what the grounding safeguard forbids (spec §6/§8). Recorded
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
        purpose: options.fetch(:purpose, :scheduled_run)
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

    # The chosen model when the credential still supports it, otherwise its
    # default supported model — a dropped model degrades gracefully instead of
    # failing the run (spec §5). The provider default is the last resort when the
    # credential exposes no verified models at all. A persisted feed records the
    # fallback once, keyed on the model actually used, so the page prompts a
    # re-pick even when the whole snapshot dropped out.
    def model_for(credential)
      chosen = feed.ai_model
      resolved = feed.effective_ai_model(credential).presence || LlmProvider.find(credential.provider).default_model

      if feed.persisted? && chosen.present? && resolved != chosen
        feed.note_ai_model_fallback!(from: chosen, to: resolved)
      end

      resolved
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
