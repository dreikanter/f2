# Appends the imported posts count to a feed refresh description, e.g.
# "My Feed refreshed (+2 posts)". Refreshes that imported nothing render plain.
class FeedRefreshDescriptionComponent < EventDescriptionComponent
  def call
    suffix = posts_count_tag
    suffix ? safe_join([super, suffix], " ") : super
  end

  private

  def posts_count_tag
    count = event.event_references.count { |reference| reference.reference_type == "Post" }
    return if count.zero?

    helpers.tag.span("(+#{helpers.pluralize(count, "post")})", class: "text-slate-400", data: { key: "events.posts_count" })
  end
end
