module PostHelper
  def post_status_badge_classes(status)
    case status.to_s
    when "enqueued"
      "bg-blue-100 text-blue-800"
    when "published"
      "bg-green-100 text-green-800"
    when "failed"
      "bg-red-100 text-red-800"
    when "rejected"
      "bg-orange-100 text-orange-800"
    else
      "bg-slate-100 text-slate-800"
    end
  end

  # TBD: Refactor after metadata/list item description pattern stabilizes
  def post_metadata_segments(post, show_feed: false, withdraw_allowed: false)
    [
      post_metadata_feed_link_segment(post, show_feed),
      post_metadata_published_segment(post),
      post_metadata_attachments_segment(post),
      post_metadata_comments_segment(post),
      post_metadata_source_link_segment(post),
      post_metadata_freefeed_link_segment(post),
      post_metadata_withdraw_link_segment(post, withdraw_allowed)
    ].compact
  end

  private

  def post_metadata_feed_link_segment(post, show_feed)
    return unless show_feed
    return unless post.feed.present?

    link_to(post.feed.name, feed_path(post.feed), class: "ff-link")
  end

  def post_metadata_published_segment(post)
    return unless post.published_at

    safe_join(["Published", time_ago_tag(post.published_at)], " ")
  end

  def post_metadata_attachments_segment(post)
    attachments_count = Array(post.attachment_urls).size
    return if attachments_count.zero?

    "Attachments: #{attachments_count}"
  end

  def post_metadata_comments_segment(post)
    comments_count = Array(post.comments).size
    return if comments_count.zero?

    "Comments: #{comments_count}"
  end

  def post_metadata_source_link_segment(post)
    return unless post.source_url.present?

    link_to("Source post", post.source_url, target: "_blank", rel: "noopener", class: "ff-link")
  end

  def post_metadata_freefeed_link_segment(post)
    return unless post.freefeed_post_id.present?

    feed = post.feed
    access_token = feed&.access_token

    return unless feed.present? && access_token.present? && feed.target_group.present?

    freefeed_url = "#{access_token.host}/#{feed.target_group}/#{post.freefeed_post_id}"
    link_to("FreeFeed post", freefeed_url, target: "_blank", rel: "noopener", class: "ff-link")
  end

  def post_metadata_withdraw_link_segment(post, withdraw_allowed)
    return unless withdraw_allowed

    link_to(
      "Withdraw",
      post_path(post),
      data: { turbo_method: :delete, turbo_confirm: "Withdraw this post? It will be removed from FreeFeed but remain visible here." },
      class: class_names("ff-link", "text-red-600 hover:text-red-500")
    )
  end
end
