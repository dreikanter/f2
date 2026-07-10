# Describes a feed refresh run by its lifecycle status, appending the imported
# posts count when there is one, e.g. "My Feed refreshed (+2 posts)".
class FeedRefreshDescriptionComponent < EventDescriptionComponent
  def call
    suffix = posts_count_tag
    suffix ? safe_join([super, suffix], " ") : super
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
end
