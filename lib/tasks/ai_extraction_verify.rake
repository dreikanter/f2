namespace :ai do
  # Live end-to-end check of the production extraction prompts (spec 005 §2/§8):
  # runs the combined system prompt + universal schema + web tools against a real
  # provider and a real source, then validates the structured result. Also a
  # smoke test of the transformation contract — the request asks for one-line
  # summaries, so the returned bodies should be short. Both credentials are
  # selected explicitly by id, so this task exercises the same managed-key path
  # as a feed run.
  desc "Verify AI extraction end-to-end with the production prompts against a live provider"
  task verify_extraction: :environment do
    provider_key = "anthropic"
    model = "claude-sonnet-4-6"

    ai_credential = AiCredential.find_by(id: ENV["AI_CREDENTIAL_ID"], provider: provider_key)
    unless ai_credential
      puts "[#{provider_key}/#{model}] SKIP: set AI_CREDENTIAL_ID to a managed #{provider_key} credential"
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
      chat = ai_credential.chat(model)
      chat.with_instructions(Loader::LlmPrompts::COMBINED_SYSTEM)
      chat.with_schema(schema)
      params = adapter.params_for(model, schema: true, web: true)
      chat.with_params(**params) if params.present?
      adapter.apply_web(
        chat,
        search_provider: search_credential.web_search_provider,
        search_credential: search_credential
      )

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
