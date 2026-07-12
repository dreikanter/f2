# Describes a feed refresh by its lifecycle status, appending the imported
# posts count and the run's AI spend when present,
# e.g. "My Feed refreshed (+2 posts) (AI: $0.03)".
class FeedRefreshDescriptionComponent < EventDescriptionComponent
  def call
    suffixes = [posts_count_tag, spend_tag].compact
    suffixes.any? ? safe_join([super, *suffixes], " ") : super
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

  def posts_count_tag
    count = event.event_references.count { |reference| reference.reference_type == "Post" }
    return if count.zero?

    helpers.tag.span("(+#{helpers.pluralize(count, "post")})", class: "text-muted", data: { key: "events.posts_count" })
  end

  # Reads the metadata snapshot, not the referenced rows, so the log renders
  # without extra queries. Absent when the run made no LLM calls; a zero-cost
  # call still shows.
  def spend_tag
    cents = event.metadata.dig("stats", "llm_cost_cents")
    return if cents.nil?

    helpers.tag.span("(AI: #{helpers.number_to_currency(cents / 100.0)})",
                     class: "text-muted", data: { key: "events.llm_cost" })
  end
end
