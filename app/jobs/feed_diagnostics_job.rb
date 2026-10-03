# Temporary research report for the feed under investigation.
class FeedDiagnosticsJob < ApplicationJob
  include RecordsJobRun
  include RunsAsMaintenanceJob

  FEED_ID = "01a1035f-d5de-71fa-ace1-5ba3fe04924b".freeze
  POST_FIELDS = %w[id feed_entry_id uid status content source_url attachment_urls comments
                   validation_errors published_at created_at updated_at reposted_at freefeed_post_id freefeed_post_url].freeze
  MESSAGE_FIELDS = %w[id role content finish_reason citations server_tool_calls raw_content created_at].freeze

  def self.description
    "Collects stored diagnostics for feed #{FEED_ID}. No API calls, refresh, or publishing."
  end

  def perform
    @feed = Feed.find(FEED_ID)
    record_event(type: "job.feed_diagnostics.completed", message: "Diagnostics for feed #{FEED_ID}", **report)
  rescue ActiveRecord::RecordNotFound
    record_event(type: "job.feed_diagnostics.failed", message: "Feed not found.", level: :error)
    raise
  end

  private

  attr_reader :feed

  def report
    report = {
      captured_at: Time.current,
      app_revision: Config.app_revision,
      environment: Rails.env,
      time_zone: Time.zone.name,
      ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s,
      scope: "All retained records for this feed. Purged records cannot be recovered.",
      feed: feed.attributes.slice(*%w[id name feed_profile_key params ai_model state images_only import_after
        refresh_interval cron_expression consecutive_failures last_successful_refresh_at imported_posts_count
        published_posts_count most_recent_post_at created_at updated_at]).merge(
          "external_search_selected" => feed.search_credential_id.present?
        ),
      schedule: feed.feed_schedule&.attributes&.slice("last_run_at", "next_run_at", "updated_at"),
      post_order: {
        source_date_desc: feed.posts.reorder(published_at: :desc).pluck(:id),
        import_time_desc: feed.posts.reorder(created_at: :desc, id: :desc).pluck(:id)
      },
      events: event_data,
      chats: chat_data,
      entries: feed.feed_entries.reorder(:created_at, :id).map do |entry|
        entry.attributes.slice("id", "uid", "status", "published_at", "created_at", "updated_at", "raw_data")
      end,
      imported_uids: FeedEntryUid.where(feed_id: feed.id).order(:imported_at, :id).map do |entry|
        entry.attributes.slice("uid", "imported_at", "created_at")
      end,
      posts: feed.posts.reorder(:created_at, :id).map { |post| post.attributes.slice(*POST_FIELDS) }
    }
    redactor.filter(report.as_json).symbolize_keys
  end

  # Follow stored event links too: search failures may live on their own events.
  def events
    return @events if defined?(@events)

    ids = feed.events.pluck(:id)
    pending = ids
    while pending.any?
      linked = EventReference.where(event_id: pending, reference_type: "Event").pluck(:reference_id)
      pending = linked - ids
      ids |= pending
    end
    @events = Event.where(id: ids).includes(:event_references).order(:created_at, :id).to_a
  end

  def event_data
    events.map do |event|
      event.attributes.slice("id", "type", "level", "subject_type", "subject_id", "message",
                             "metadata", "created_at", "updated_at").merge(
        "references" => event.event_references.map { |ref| ref.attributes.slice("reference_type", "reference_id") }
      )
    end
  end

  def chat_data
    linked_ids = events.flat_map(&:event_references).filter_map do |ref|
      ref.reference_id if ref.reference_type == "LlmChat"
    end
    LlmChat.where(feed_id: feed.id).or(LlmChat.where(id: linked_ids)).order(:created_at, :id).map do |chat|
      chat.attributes.slice(*%w[id purpose requested_provider requested_model status started_at deadline_at
        finished_at error_category created_at updated_at]).merge(
          "messages" => message_data(chat),
          "usage" => usage_data(chat)
        )
    end
  end

  def message_data(chat)
    chat.messages.reorder(:created_at, :id).select(*MESSAGE_FIELDS).map do |message|
      message.attributes.except("server_tool_calls", "raw_content").merge(
        "server_tool_calls" => Array(message[:server_tool_calls]).map do |call|
          call.slice("type", "id", "name", "input", "result").merge(
            "raw" => (call["raw"] || call).slice("type", "id", "status", "action", "results")
          )
        end,
        "raw_content" => Array(message[:raw_content]).filter_map do |part|
          part.slice("type", "text", "refusal", "annotations") if part.is_a?(Hash)
        end
      )
    end
  end

  def usage_data(chat)
    chat.ruby_llm_usages.reorder(:created_at, :id).map do |usage|
      usage.attributes.slice(*%w[id message_id operation provider model status input_tokens output_tokens
        cache_read_tokens cache_write_tokens thinking_tokens input_cost output_cost cache_read_cost
        cache_write_cost thinking_cost total_cost created_at])
    end
  end

  def redactor
    # Exact keys preserve useful diagnostic counters such as input_tokens.
    ActiveSupport::ParameterFilter.new([
      /\A(?:credential_data|api_key|access_token|refresh_token|password|authorization|secret|thinking_text|thinking_signature|raw_reasoning)\z/i,
      lambda do |_key, value|
        value.gsub!(/\bsk-[\w-]+|\bBearer\s+[\w.\-]+/i, "[FILTERED]") if value.is_a?(String)
      end
    ])
  end
end
