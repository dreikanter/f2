class PostsListComponent < ViewComponent::Base
  def initialize(posts:, show_feed: false, empty_text: "No posts yet.")
    @posts = posts
    @show_feed = show_feed
    @empty_text = empty_text
  end

  def render_list
    component = ListGroupComponent.new

    @posts.each do |post|
      component.with_item(ListGroupComponent::PostItemComponent.new(
        icon: helpers.post_status_icon(post.status),
        title: helpers.post_content_preview(post.content, 80),
        title_url: helpers.post_path(post),
        metadata_segments: metadata_segments_for(post),
        key: helpers.dom_id(post)
      ))
    end

    component
  end

  def render_empty_state
    content_tag(:p, @empty_text, class: "ff-text text-slate-500")
  end

  private

  def metadata_segments_for(post)
    withdraw_allowed = helpers.policy(post).destroy?

    [
      feed_link_segment(post),
      published_segment(post),
      attachments_segment(post),
      comments_segment(post),
      source_link_segment(post),
      freefeed_link_segment(post),
      withdraw_link_segment(post, withdraw_allowed)
    ].compact
  end

  def feed_link_segment(post)
    return unless @show_feed
    return unless post.feed.present?

    helpers.link_to(post.feed.name, helpers.feed_path(post.feed), class: "ff-link")
  end

  def published_segment(post)
    return unless post.published_at

    helpers.safe_join(["Published", helpers.time_ago_tag(post.published_at)], " ")
  end

  def attachments_segment(post)
    attachments_count = Array(post.attachment_urls).size
    return if attachments_count.zero?

    "Attachments: #{attachments_count}"
  end

  def comments_segment(post)
    comments_count = Array(post.comments).size
    return if comments_count.zero?

    "Comments: #{comments_count}"
  end

  def source_link_segment(post)
    return unless post.source_url.present?

    helpers.link_to("Source post", post.source_url, target: "_blank", rel: "noopener", class: "ff-link")
  end

  def freefeed_link_segment(post)
    return unless post.freefeed_post_id.present?

    feed = post.feed
    access_token = feed&.access_token

    return unless feed.present? && access_token.present? && feed.target_group.present?

    freefeed_url = "#{access_token.host}/#{feed.target_group}/#{post.freefeed_post_id}"
    helpers.link_to("FreeFeed post", freefeed_url, target: "_blank", rel: "noopener", class: "ff-link")
  end

  def withdraw_link_segment(post, withdraw_allowed)
    return unless withdraw_allowed

    helpers.link_to(
      "Withdraw",
      helpers.post_path(post),
      data: { turbo_method: :delete, turbo_confirm: "Withdraw this post? It will be removed from FreeFeed but remain visible here." },
      class: helpers.class_names("ff-link", "text-red-600 hover:text-red-500")
    )
  end
end
