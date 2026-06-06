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

  def source_label
    return unless post.published_at
    label_with_time("Source", post.published_at)
  end

  def repost_label
    return unless post.reposted_at
    label_with_time("Repost", post.reposted_at)
  end

  def label_with_time(label, time)
    helpers.safe_join([label, " (", helpers.short_time_ago_tag(time), ")"])
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

  def delete_allowed?
    helpers.policy(post).destroy?
  end

  def withdrawn?
    post.status.to_s == "withdrawn"
  end

  def card_classes
    helpers.class_names(
      "w-full rounded-lg border border-slate-200 shadow-xs",
      "bg-slate-50" => withdrawn?,
      "bg-white" => !withdrawn?
    )
  end

  def delete_modal_id
    PostDeleteModalComponent.modal_id(post)
  end

  def menu_id
    "post-menu-#{post.id}"
  end
end
