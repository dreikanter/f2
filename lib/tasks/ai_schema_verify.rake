namespace :ai do
  # One-off live check that each configured provider accepts the digest output
  # schema — specifically the nullable `source_url` union (spec 005 §3) that
  # Anthropic's structured output must accept and the model must be able to emit
  # as JSON null. Run on staging via `kamal app exec` where the API keys live.
  # Read-only apart from the one LlmUsage row each call records.
  desc "Verify the AI output schema (nullable source_url) against live providers"
  task verify_digest_schema: :environment do
    schema = FeedProfile::UNIVERSAL_OUTPUT_SCHEMA
    prompt = <<~PROMPT
      Return a JSON object with an "items" array of exactly two items.
      Item 1 (feed-style): body "First real post", source_url "https://example.com/1".
      Item 2 (digest/roundup with no single link): body "A summary of several sources",
      and source_url set to JSON null. Do not include a uid field.
    PROMPT

    checks = [%w[anthropic claude-sonnet-4-6], %w[moonshot kimi-k2.5]]

    checks.each do |provider, model|
      credential = AiCredential.active.find_by(provider: provider)
      unless credential
        puts "[#{provider}/#{model}] SKIP: no active credential on this environment"
        next
      end

      begin
        client = LlmClient.new(credential)
        ctx = LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader, model: model, purpose: :preview)
        # web:false keeps the check cheap and focused: schema acceptance is
        # independent of the web tools the real loader adds.
        payload = client.call(ctx, prompt: prompt, output_schema: schema, web: false).payload
        items = Array(payload["items"])
        null_sources = items.count { |item| item["source_url"].nil? }

        puts "[#{provider}/#{model}] PASS: schema accepted; #{items.size} items, #{null_sources} with null source_url"
        items.each_with_index do |item, i|
          puts "    item #{i}: source_url=#{item['source_url'].inspect} body=#{item['body'].to_s[0, 48].inspect}"
        end
      rescue StandardError => e
        puts "[#{provider}/#{model}] FAIL: #{e.class}: #{e.message}"
      end
    end
  end
end
