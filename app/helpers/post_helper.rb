module PostHelper
  def post_metadata_segments(post, show_feed: false, withdraw_allowed: false)
    segments = []

    if show_feed && post.feed.present?
      segments << link_to(post.feed.name, feed_path(post.feed), class: "ff-link")
    end

    if post.published_at
      segments << safe_join(["Published", time_ago_tag(post.published_at)], " ")
    end

    attachments_count = Array(post.attachment_urls).size
    segments << "Attachments: #{attachments_count}"

    comments_count = Array(post.comments).size
    segments << "Comments: #{comments_count}"

    if post.source_url.present?
      segments << link_to("Source post", post.source_url, target: "_blank", rel: "noopener", class: "ff-link")
    end

    if post.freefeed_post_id.present? && post.feed.access_token.present? && post.feed.target_group.present?
      freefeed_url = "#{post.feed.access_token.host}/#{post.feed.target_group}/#{post.freefeed_post_id}"
      segments << link_to("FreeFeed post", freefeed_url, target: "_blank", rel: "noopener", class: "ff-link")
    end

    if withdraw_allowed
      segments << link_to("Withdraw",
                          post_path(post),
                          data: { turbo_method: :delete, turbo_confirm: "Withdraw this post? It will be removed from FreeFeed but remain visible here." },
                          class: class_names("ff-link", "text-red-600 hover:text-red-500"))
    end

    segments
  end
end
