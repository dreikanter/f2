class PostsListComponent < ViewComponent::Base
  def initialize(posts:, show_feed: false, empty_text: "No posts yet.")
    @posts = posts
    @show_feed = show_feed
    @empty_text = empty_text
  end

  def call
    if @posts.any?
      render_list
    else
      render_empty_state
    end
  end

  private

  def render_list
    component = ListGroupComponent.new
    @posts.each do |post|
      component.with_item(PostItemComponent.new(
        post: post,
        show_feed: @show_feed,
        withdraw_allowed: helpers.policy(post).destroy?
      ))
    end
    render(component)
  end

  def render_empty_state
    content_tag(:p, @empty_text, class: "ff-text text-slate-500")
  end

  class PostItemComponent < ViewComponent::Base
    DEFAULT_ITEM_CLASS = "flex flex-col gap-2 p-4 sm:flex-row sm:items-start sm:gap-4"
    CONTENT_WRAPPER_CLASSES = "flex items-start gap-3 sm:flex-1"
    ICON_CLASSES = "inline-flex shrink-0 text-slate-500"
    INNER_WRAPPER_CLASSES = "flex flex-1 flex-col gap-1"
    TITLE_CLASSES = "inline-flex items-start text-base font-semibold text-slate-900 transition hover:text-slate-700 ff-focus-ring"
    METADATA_CLASSES = "ff-text flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-slate-500"
    BULLET_CLASSES = "text-slate-300"

    def initialize(post:, show_feed: false, withdraw_allowed: false)
      @post = post
      @show_feed = show_feed
      @withdraw_allowed = withdraw_allowed
    end

    def call
      content_tag :li, class: DEFAULT_ITEM_CLASS do
        content_tag(:div, class: CONTENT_WRAPPER_CLASSES) do
          safe_join([icon_span, inner_wrapper])
        end
      end
    end

    private

    def icon_span
      content_tag(:span, helpers.post_status_icon(@post.status), class: ICON_CLASSES)
    end

    def inner_wrapper
      content_tag(:div, class: INNER_WRAPPER_CLASSES) do
        safe_join([title_link, metadata_div])
      end
    end

    def title_link
      helpers.link_to(
        helpers.post_content_preview(@post.content, 80),
        helpers.post_path(@post),
        class: TITLE_CLASSES
      )
    end

    def metadata_div
      segments = metadata_segments
      return if segments.empty?

      content_tag(:div, class: METADATA_CLASSES) do
        parts = segments.flat_map.with_index do |segment, index|
          result = []
          result << content_tag(:span, "&bull;".html_safe, "aria-hidden": true, class: BULLET_CLASSES) if index.positive?
          result << content_tag(:span, segment)
          result
        end
        safe_join(parts)
      end
    end

    def metadata_segments
      [
        feed_link_segment,
        published_segment,
        attachments_segment,
        comments_segment,
        source_link_segment,
        freefeed_link_segment,
        withdraw_link_segment
      ].compact
    end

    def feed_link_segment
      return unless @show_feed
      return unless @post.feed.present?

      helpers.link_to(@post.feed.name, helpers.feed_path(@post.feed), class: "ff-link")
    end

    def published_segment
      return unless @post.published_at

      safe_join(["Published", helpers.time_ago_tag(@post.published_at)], " ")
    end

    def attachments_segment
      attachments_count = Array(@post.attachment_urls).size
      return if attachments_count.zero?

      "Attachments: #{attachments_count}"
    end

    def comments_segment
      comments_count = Array(@post.comments).size
      return if comments_count.zero?

      "Comments: #{comments_count}"
    end

    def source_link_segment
      return unless @post.source_url.present?

      helpers.link_to("Source post", @post.source_url, target: "_blank", rel: "noopener", class: "ff-link")
    end

    def freefeed_link_segment
      return unless @post.freefeed_post_id.present?

      feed = @post.feed
      access_token = feed&.access_token

      return unless feed.present? && access_token.present? && feed.target_group.present?

      freefeed_url = "#{access_token.host}/#{feed.target_group}/#{@post.freefeed_post_id}"
      helpers.link_to("FreeFeed post", freefeed_url, target: "_blank", rel: "noopener", class: "ff-link")
    end

    def withdraw_link_segment
      return unless @withdraw_allowed

      helpers.link_to(
        "Withdraw",
        helpers.post_path(@post),
        data: { turbo_method: :delete, turbo_confirm: "Withdraw this post? It will be removed from FreeFeed but remain visible here." },
        class: helpers.class_names("ff-link", "text-red-600 hover:text-red-500")
      )
    end
  end
end
