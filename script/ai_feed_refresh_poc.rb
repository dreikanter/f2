# frozen_string_literal: true

# Temporary research script; discard after live validation.
# bin/rails runner -e development script/ai_feed_refresh_poc.rb
# Pass a prompt as the first argument to replace the default.

abort "Run with bin/rails runner -e development." unless Rails.env.development?

Rails.logger = Logger.new(File::NULL)
RubyLLM.configure { |config| config.logger = Logger.new(File::NULL) }
workflow = nil

begin
  credential = AiCredential.first!
  abort "The first AI credential must be active and use OpenAI." unless credential.active? && credential.provider == "openai"

  # Both the publication job and scheduler exclude disabled feeds.
  feed = Feed.create!(
    user: credential.user,
    name: "AI refresh PoC #{SecureRandom.hex(4)}",
    state: :disabled,
    access_token: nil,
    target_group: nil,
    ai_credential: credential,
    ai_model: "gpt-6-luna",
    feed_profile_key: "llm",
    params: {
      "max_items" => 2,
      "prompt" => ARGV.first || <<~TEXT
        Find the latest stable release announcements for Ruby and Ruby on Rails.
        Return one short feed post for each, including the version, release date,
        and a link to the official announcement.
      TEXT
    }
  )

  warn "Two live Luna requests. The diagnostic feed stays disabled; nothing will be published."
  2.times do |index|
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    workflow = FeedRefreshWorkflow.new(feed)
    workflow.execute

    chat = feed.llm_chats.order(:created_at).last!
    event = feed.events.where(type: "feed_refresh").order(:created_at).last!
    items = JSON.parse(chat.messages.where(role: "assistant").last!.content).fetch("items")

    puts JSON.pretty_generate(
      run: index + 1,
      feed_id: feed.id,
      feed_state: feed.reload.state,
      elapsed_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3),
      refresh_status: event.metadata.fetch("status"),
      stats: event.metadata.fetch("stats").slice("total_entries", "new_entries", "new_posts", "rejected_posts"),
      returned_items: items,
      saved_entries: feed.feed_entries.count,
      saved_uids: FeedEntryUid.where(feed_id: feed.id).count,
      saved_posts: feed.posts.order(:created_at).map do |post|
        post.attributes.slice("uid", "content", "source_url", "status", "validation_errors")
      end,
      chat_status: chat.status,
      usage: chat.ruby_llm_usages.map do |usage|
        usage.attributes.slice("provider", "model", "status", "input_tokens", "output_tokens", "total_cost")
          .merge("web_search_calls" => LlmUsageDetails.new(usage).web_search_count)
      end
    )
  end
rescue StandardError => error
  puts JSON.pretty_generate(error: error.class.name, stage: workflow&.current_step)
  exit 1
end
