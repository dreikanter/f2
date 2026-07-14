namespace :ai do
  # One-off live check that each configured provider accepts the digest output
  # schema — specifically the nullable `source_url` union (spec 005 §3) that
  # Anthropic's structured output must accept and the model must be able to emit
  # as JSON null. Uses the capability-probe provider so it reads the same ENV
  # keys the probe jobs use on staging. If a provider rejects the schema, the
  # `.ask` call raises and is reported as FAIL.
  desc "Verify the AI output schema (nullable source_url) against live providers"
  task verify_digest_schema: :environment do
    schema = FeedProfile::UNIVERSAL_OUTPUT_SCHEMA
    prompt = <<~PROMPT
      Return a JSON object with an "items" array of exactly two items.
      Item 1 (feed-style): body "First real post", source_url "https://example.com/1".
      Item 2 (a digest/roundup with no single link): body "A summary of several sources",
      and source_url set to JSON null. Do not include a uid field.
    PROMPT

    [%w[anthropic claude-sonnet-4-6], %w[moonshot kimi-k2.5]].each do |provider_key, model|
      unless LlmCapabilityProbe::Provider.configured?(provider_key)
        puts "[#{provider_key}/#{model}] SKIP: no API key in environment"
        next
      end

      begin
        provider = LlmCapabilityProbe::Provider.build(provider_key)
        raw = provider.chat(model).with_schema(schema).ask(prompt).content
        payload = raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
        errors = JSONSchemer.schema(schema).validate(payload).to_a
        items = payload.is_a?(Hash) ? Array(payload["items"]) : []
        null_sources = items.count { |item| item["source_url"].nil? }

        verdict = errors.empty? ? "PASS (schema accepted)" : "FAIL (schema violation: #{errors.first['error']})"
        puts "[#{provider_key}/#{model}] #{verdict}: #{items.size} items, #{null_sources} with null source_url"
        items.each_with_index do |item, i|
          puts "    item #{i}: source_url=#{item['source_url'].inspect} body=#{item['body'].to_s[0, 48].inspect}"
        end
      rescue StandardError => e
        puts "[#{provider_key}/#{model}] FAIL: #{e.class}: #{e.message.to_s[0, 300]}"
      end
    end
  end

  # Live end-to-end check of the production extraction prompts (spec 005 §2/§8):
  # runs the combined system prompt + universal schema + web tools against a real
  # provider and a real source, then validates the structured result. Also a
  # smoke test of the transformation contract — the request asks for one-line
  # summaries, so the returned bodies should be short. The search credential is
  # selected explicitly so this task exercises the same managed-key path as a
  # feed run.
  desc "Verify AI extraction end-to-end with the production prompts against a live provider"
  task verify_extraction: :environment do
    provider_key = "anthropic"
    model = "claude-sonnet-4-6"

    unless LlmCapabilityProbe::Provider.configured?(provider_key)
      puts "[#{provider_key}/#{model}] SKIP: no AI provider API key in environment"
      next
    end

    search_credential = SearchCredential.active.find_by(id: ENV["SEARCH_CREDENTIAL_ID"])
    unless search_credential
      puts "[#{provider_key}/#{model}] SKIP: set SEARCH_CREDENTIAL_ID to an active managed credential"
      next
    end

    schema = FeedProfile::UNIVERSAL_OUTPUT_SCHEMA
    adapter = LlmClient::Adapter.for(provider_key)
    user_prompt = <<~PROMPT
      Feed request — what to follow and how to present it:

      Follow the Ruby on Rails blog at https://rubyonrails.org/blog and return its
      most recent posts. Rewrite each post's body as a single one-line summary.
    PROMPT

    begin
      chat = LlmCapabilityProbe::Provider.build(provider_key).chat(model)
      chat.with_instructions(Loader::LlmPrompts::COMBINED_SYSTEM)
      chat.with_schema(schema)
      search_tool = LlmClient::Tools::WebSearch.new(
        provider: search_credential.web_search_provider,
        credential: search_credential,
        purpose: :validation
      )
      adapter.apply_web(chat, model, search_tool: search_tool)

      raw = chat.ask(user_prompt).content
      payload = raw.is_a?(Hash) ? raw : JSON.parse(adapter.unwrap_json(raw.to_s))
      errors = JSONSchemer.schema(schema).validate(payload).to_a
      items = Array(payload["items"])

      verdict = errors.empty? ? "PASS (schema accepted)" : "FAIL (schema violation: #{errors.first['error']})"
      puts "[#{provider_key}/#{model}] #{verdict}: #{items.size} items"
      items.first(5).each_with_index do |item, i|
        puts "    item #{i}: source_url=#{item['source_url'].inspect} body=#{item['body'].to_s[0, 90].inspect}"
      end
    rescue StandardError => e
      puts "[#{provider_key}/#{model}] FAIL: #{e.class}: #{e.message.to_s[0, 300]}"
    end
  end
end
