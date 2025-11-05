module PostHelper
  def format_post_content(content)
    return "" if content.blank?

    # Trim leading and trailing whitespace
    trimmed = content.strip

    # Split by 2+ line breaks to create paragraphs
    paragraphs = trimmed.split(/\n{2,}/)

    # Process each paragraph
    formatted_paragraphs = paragraphs.map do |para|
      # Escape HTML to prevent XSS
      escaped = ERB::Util.html_escape(para)

      # Convert URLs to links
      linked = auto_link_urls(escaped)

      # Convert single line breaks to <br> tags
      with_breaks = linked.gsub(/\n/, "<br>")

      # Wrap in paragraph tag
      tag.p(with_breaks.html_safe, class: "mb-4 last:mb-0")
    end

    safe_join(formatted_paragraphs)
  end

  def post_status_badge_color(status)
    case status.to_s
    when "enqueued"
      :blue
    when "published"
      :green
    when "failed"
      :red
    when "rejected"
      :orange
    else
      :gray
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

  # Convert URLs in text to clickable links
  def auto_link_urls(text)
    # Regex to match URLs (http, https, ftp)
    url_regex = %r{
      \b
      (https?://|ftp://)
      [^\s<>]+
    }x

    text.gsub(url_regex) do |url|
      %(<a href="#{url}" target="_blank" rel="noopener" class="ff-link">#{url}</a>)
    end
  end

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
