class PostCardComponent < ViewComponent::Base
  def initialize(post:, show_feed: false)
    @post = post
    @show_feed = show_feed
  end

  private

  attr_reader :post, :show_feed

  def title
    helpers.post_content_preview(post.content, 160)
  end

  def post_url
    helpers.post_path(post)
  end

  def group_label
    return unless show_feed
    group = post.feed&.target_group
    "@#{group}" if group.present?
  end

  def group_url
    return unless show_feed && post.feed
    helpers.feed_path(post.feed)
  end

  def group_hint
    post.feed&.display_name
  end

  def published_time_tag
    return unless post.published_at
    helpers.short_time_ago_tag(post.published_at)
  end

  def reposted_time_tag
    return unless post.reposted_at
    helpers.short_time_ago_tag(post.reposted_at)
  end

  def attachment_count
    Array(post.attachment_urls).size
  end

  def comment_count
    Array(post.comments).size
  end

  def source_url
    post.source_url.presence
  end

  def freefeed_url
    post.freefeed_url
  end

  def withdraw_allowed?
    helpers.policy(post).destroy?
  end

  def withdrawn?
    post.status.to_s == "withdrawn"
  end

  def footer?
    published_time_tag || group_label.present? || attachment_count > 0 || comment_count > 0 || source_url || freefeed_url || withdraw_allowed?
  end

  def menu_id
    "post-menu-#{post.id}"
  end
end
