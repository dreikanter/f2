# frozen_string_literal: true

# Temporary application check; discard after live validation.
# bin/rails runner -e development script/ai_feed_poc.rb

abort "Run with bin/rails runner -e development." unless Rails.env.development?

Rails.logger = Logger.new(File::NULL)
RubyLLM.configure { |config| config.logger = Logger.new(File::NULL) }

begin
  credential = AiCredential.first!
  abort "The first AI credential must be active and use OpenAI." unless credential.active? && credential.provider == "openai"

  started_at = Time.current
  preview = FeedPreview.create!(
    user: credential.user, ai_credential: credential, ai_model: "gpt-6-luna",
    feed_profile_key: "llm", status: :pending, run_id: SecureRandom.uuid,
    params: {
      "max_items" => 2,
      "prompt" => <<~TEXT
        Find the latest stable release announcements for Ruby and Ruby on Rails.
        Return one short feed post for each, including the version, release date,
        and a link to the official announcement.
      TEXT
    }
  )

  warn "Running the application preview with gpt-6-luna. Nothing will be published."
  FeedPreviewWorkflow.new(preview, run_id: preview.run_id).execute
  chat = credential.llm_chats.where(purpose: :preview, started_at: started_at..).sole

  puts JSON.pretty_generate(
    elapsed_seconds: (Time.current - started_at).round(3),
    preview_status: preview.reload.status,
    posts: preview.posts_data,
    chat_status: chat.status,
    requested_model: chat.requested_model,
    usage: chat.ruby_llm_usages.map do |usage|
      usage.attributes.slice("provider", "model", "status", "input_tokens", "output_tokens", "total_cost")
        .merge("web_search_calls" => LlmUsageDetails.new(usage).web_search_count)
    end
  )
rescue StandardError => error
  puts JSON.pretty_generate(error: error.class.name)
  exit 1
end
