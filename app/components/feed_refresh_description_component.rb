# Describes a feed refresh run by its lifecycle status, appending the imported
# posts count when there is one, e.g. "My Feed refreshed (+2 posts)".
class FeedRefreshDescriptionComponent < EventDescriptionComponent
  def call
    suffix = posts_count_tag
    suffix ? safe_join([super, suffix], " ") : super
  end

  private

  # Events predating the status lifecycle have no status; they were completed runs.
  def description_key
    case event.metadata["status"]
    when "started" then "events.feed_refresh.started_description_html"
    when "failed" then "events.feed_refresh.failed_description_html"
    when "interrupted" then "events.feed_refresh.interrupted_description_html"
    else super
    end
  end

  def posts_count_tag
    count = event.event_references.count { |reference| reference.reference_type == "Post" }
    return if count.zero?

    helpers.tag.span("(+#{helpers.pluralize(count, "post")})", class: "text-muted", data: { key: "events.posts_count" })
  end
end
