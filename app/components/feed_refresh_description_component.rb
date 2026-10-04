# Describes a feed refresh by its lifecycle status, appending the
# result and the run's AI spend when present,
# e.g. "My Feed refreshed · 2 new posts · 1 entry already imported · AI usage: $0.03".
class FeedRefreshDescriptionComponent < EventDescriptionComponent
  def call
    suffixes = [result_tag, already_imported_tag, spend_tag].compact
    safe_join([super, *suffixes], helpers.middot)
  end

  private

  # A nil status is a legacy event from before the lifecycle; those were
  # completed runs. An unrecognized status must not fall through to the
  # success copy.
  def description_key
    case event.metadata["status"]
    when "started" then "events.feed_refresh.started_description_html"
    when "failed" then "events.feed_refresh.failed_description_html"
    when "interrupted" then "events.feed_refresh.interrupted_description_html"
    when "completed", nil then super
    else "events.feed_refresh.unknown_status_description_html"
    end
  end

  def result_tag
    text = result_text
    return if text.nil?

    helpers.tag.span(text, class: "text-muted", data: { key: "events.posts_count" })
  end

  def result_text
    stats = event.metadata.fetch("stats", {})
    count = stats.fetch("new_posts") do
      event.event_references.count { |reference| reference.reference_type == "Post" }
    end
    return helpers.pluralize(count, "new post") unless count.zero?
    return unless ["completed", nil].include?(event.metadata["status"]) && stats.key?("total_entries")
    return if only_previously_imported_entries?(stats)

    stats["total_entries"].zero? ? "no entries returned" : "no new posts"
  end

  def only_previously_imported_entries?(stats)
    imported = stats["already_imported_entries"].to_i
    imported.positive? && stats["total_entries"] == imported + stats["collapsed_duplicate_uids"].to_i
  end

  def already_imported_tag
    count = event.metadata.dig("stats", "already_imported_entries").to_i
    return if count.zero?

    helpers.tag.span("#{helpers.pluralize(count, "entry")} already imported",
                     class: "text-muted", data: { key: "events.already_imported" })
  end

  # Reads the metadata snapshot, not the referenced rows, so the log renders
  # without extra queries. Absent when the run made no LLM calls; a zero-cost
  # call still shows.
  def spend_tag
    cents = event.metadata.dig("stats", "llm_cost_cents")
    return if cents.nil? && event.metadata.dig("stats", "llm_calls").to_i.zero?

    cost = cents.nil? ? "unknown cost" : helpers.number_to_currency(cents / 100.0)
    helpers.tag.span("AI usage: #{cost}",
                     class: "text-muted", data: { key: "events.llm_cost" })
  end
end
