# frozen_string_literal: true

# Temporary application check; discard after live validation.
# bin/rails runner -e development script/ai_feed_application_poc.rb
# Pass a prompt as the first argument to replace the default.

abort "Run with bin/rails runner -e development." unless Rails.env.development?

Rails.logger = Logger.new(File::NULL)
RubyLLM.configure { |config| config.logger = Logger.new(File::NULL) }

begin
  credential = AiCredential.first!
  abort "The first AI credential must be active and use OpenAI." unless credential.active? && credential.provider == "openai"

  prompt = ARGV.first || <<~TEXT
    Return two short posts:
    - Summarize https://xkcd.com/353/, link to it, attach its actual comic image,
      and include its original publication date and author credit.
      If the image cannot be retrieved, return the post with no images.
    - Write an original two-sentence story about an astronomer hearing a star
      reply. This post should have no source link, publication date, or image.
  TEXT
  feed = Feed.new(
    user: credential.user, ai_credential: credential, ai_model: "gpt-6-luna",
    feed_profile_key: "llm", state: :disabled,
    params: { "prompt" => prompt, "max_items" => 2 }
  )

  warn "One live Luna request through the application. Database changes will be rolled back; nothing will be published."
  report = nil
  ApplicationRecord.transaction do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    raw_data = feed.loader_instance(purpose: :preview).load
    entries = feed.processor_instance(raw_data).process.entries
    report = {
      requested_model: feed.ai_model,
      elapsed_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3),
      posts: entries.map do |entry|
        feed.normalizer_instance(entry).normalize.normalized_attributes
      end
    }
    raise ActiveRecord::Rollback
  end
  puts JSON.pretty_generate(report)
rescue StandardError => error
  puts JSON.pretty_generate(error: error.class.name)
  exit 1
end
