class PostsListComponent < ViewComponent::Base
  def initialize(posts:, show_feed: false)
    @posts = posts
    @show_feed = show_feed
  end

  def call
    render render_list
  end

  def render_list
    component = ListComponent.new

    @posts.each do |post|
      component.with_item(self.class.item_component(post:, helpers: helpers, show_feed: @show_feed))
    end

    component
  end

  def self.item_component(post:, helpers:, show_feed: false)
    ListComponent::ItemComponent.new(
      title: helpers.post_content_preview(post.content, 80),
      title_url: helpers.post_path(post),
      metadata_segments: metadata_segments_for(post:, helpers:, show_feed:),
      key: helpers.dom_id(post)
    )
  end

  def self.metadata_segments_for(post:, helpers:, show_feed: false)
    withdraw_allowed = helpers.policy(post).destroy?

    [
      feed_link_segment(post:, helpers:, show_feed:),
      status_segment(post:),
      published_segment(post:, helpers:),
      attachments_segment(post:),
      comments_segment(post:),
      source_link_segment(post:, helpers:),
      freefeed_link_segment(post:, helpers:),
      withdraw_link_segment(post:, helpers:, withdraw_allowed:)
    ].compact
  end

  def self.status_segment(post:)
    "Withdrawn" if post.status.to_s == "withdrawn"
  end

  def self.feed_link_segment(post:, helpers:, show_feed: false)
    return unless show_feed
    return unless post.feed.present?

    helpers.link_to(post.feed.name, helpers.feed_path(post.feed), class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500")
  end

  def self.published_segment(post:, helpers:)
    return unless post.published_at

    time_html = helpers.content_tag(
      :time,
      "#{helpers.short_time_ago(post.published_at)} ago",
      datetime: post.published_at.rfc3339,
      title: helpers.long_time_format(post.published_at)
    )
    helpers.safe_join(["Published", time_html], " ")
  end

  def self.attachments_segment(post:)
    attachments_count = Array(post.attachment_urls).size
    return if attachments_count.zero?

    "Attachments: #{attachments_count}"
  end

  def self.comments_segment(post:)
    comments_count = Array(post.comments).size
    return if comments_count.zero?

    "Comments: #{comments_count}"
  end

  def self.source_link_segment(post:, helpers:)
    return unless post.source_url.present?

    helpers.link_to("Source post", post.source_url, target: "_blank", rel: "noopener", class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500")
  end

  def self.freefeed_link_segment(post:, helpers:)
    return unless post.freefeed_post_id.present?

    feed = post.feed
    access_token = feed&.access_token

    return unless feed.present? && access_token.present? && feed.target_group.present?

    freefeed_url = "#{access_token.host}/#{feed.target_group}/#{post.freefeed_post_id}"
    helpers.link_to("FreeFeed post", freefeed_url, target: "_blank", rel: "noopener", class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500")
  end

  def self.withdraw_link_segment(post:, helpers:, withdraw_allowed:)
    return unless withdraw_allowed

    helpers.link_to(
      "Withdraw",
      helpers.post_path(post),
      data: { turbo_method: :delete, turbo_confirm: "Withdraw this post? It will be removed from FreeFeed but remain visible here." },
      class: "font-medium underline underline-offset-4 transition text-red-600 hover:text-red-500"
    )
  end
end
