# TEMPORARY end-to-end smoke test for the Moonshot/Kimi adapter (PR #917),
# run from the dev jobs runner on staging. Delete once Kimi is confirmed.
#
# Records two checks so one run diagnoses both the adapter and the prompt:
#   A) the real Loader::LlmLoader path with the shipped profile prompt;
#   B) a direct two-step call with an explicit fetch-tool prompt (isolates the
#      adapter mechanism from prompt wording).
class KimiSmokeJob < ApplicationJob
  include RecordsJobRun

  queue_as :default

  PROFILE = "llm_website_extractor".freeze
  SOURCE_URL = "https://rubyonrails.org/blog".freeze
  TOOL_PROMPT = "Use the fetch tool to read #{SOURCE_URL}, then return the latest posts you find there. " \
                "For each: a stable permalink as uid, a title, a one-sentence body, and the source_url.".freeze

  def perform
    key = ENV["MOONSHOT_API_KEY"].to_s
    return record_event(type: "job.kimi_smoke.skipped", message: "no MOONSHOT_API_KEY", level: :warning) if key.blank?

    credential = AiCredential.create!(user: user, provider: "moonshot", state: :active,
                                      credential_data: { "api_key" => key })
    check_loader(credential)
    check_direct(credential)
  ensure
    cleanup(credential)
  end

  private

  def user
    User.order(:id).first
  end

  # A) Full production path.
  def check_loader(credential)
    feed = Feed.new(user: user, ai_credential: credential, feed_profile_key: PROFILE,
                    params: { "url" => SOURCE_URL })
    items = Loader::LlmLoader.new(feed).load
    report("loader", items)
  rescue StandardError => e
    error("loader", e)
  end

  # B) Adapter mechanism with an explicit fetch-tool prompt.
  def check_direct(credential)
    client = LlmClient.new(credential)
    ctx = LlmClient::CallContext.new(feed: nil, profile_key: PROFILE, stage: :loader,
                                     model: LlmProvider.find("moonshot").default_model, purpose: :preview)
    gathered = client.call(ctx, prompt: TOOL_PROMPT, output_schema: nil, web: true).payload
    payload = client.call(ctx, prompt: structuring_prompt(gathered),
                          output_schema: FeedProfile::UNIVERSAL_OUTPUT_SCHEMA, web: false).payload
    report("direct", Array(payload["items"]), gathered: gathered)
  rescue StandardError => e
    error("direct", e)
  end

  def structuring_prompt(gathered)
    "Convert the gathered content below into the required JSON object. Use only what is present.\n\n#{gathered}"
  end

  def report(check, items, gathered: nil)
    grounded = items.any? { |i| i["source_url"].to_s.match?(%r{\Ahttps?://}) }
    record_event(type: "job.kimi_smoke.result",
                 message: "#{check}: #{items.size} item(s), grounded=#{grounded}",
                 level: grounded ? :info : :warning, check: check,
                 items: items.first(3), gathered_preview: gathered&.slice(0, 1000))
  end

  def error(check, exception)
    record_event(type: "job.kimi_smoke.error", message: "#{check}: #{exception.class}: #{exception.message[0, 300]}",
                 level: :warning, check: check)
  end

  def cleanup(credential)
    return unless credential&.persisted?

    LlmUsage.where(ai_credential: credential).delete_all
    credential.destroy
  end
end
