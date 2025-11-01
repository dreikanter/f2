class PostDetailsComponent < ViewComponent::Base
  def initialize(post:)
    @post = post
  end

  def call
    component = ListGroupComponent.new

    add_feed_item(component)
    add_published_item(component)
    add_attachments_item(component) if @post.attachment_urls.present?
    add_comments_item(component) if @post.comments.present?
    add_source_url_item(component)
    add_validation_errors_item(component) if @post.validation_errors.present?
    add_uid_item(component)
    add_freefeed_post_id_item(component) if @post.freefeed_post_id.present?

    render(component)
  end

  private

  def add_feed_item(component)
    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Feed:",
      value: helpers.link_to(@post.feed.name, @post.feed, class: "ff-link"),
      key: "post.feed"
    ))
  end

  def add_published_item(component)
    value = @post.published_at ? helpers.long_time_tag(@post.published_at) : content_tag(:span, "Not published", class: "text-slate-500")
    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Published:",
      value: value,
      key: "post.published"
    ))
  end

  def add_attachments_item(component)
    attachments_html = safe_join(
      @post.attachment_urls.map do |url|
        helpers.link_to(url, target: "_blank", rel: "noopener", class: "ff-link inline-flex items-center") do
          helpers.icon("file-earmark-image", aria_hidden: true)
        end
      end,
      " "
    )

    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Attachments (#{@post.attachment_urls.length}):",
      value: attachments_html,
      key: "post.attachments"
    ))
  end

  def add_comments_item(component)
    comments_html = safe_join(
      @post.comments.map do |comment|
        content_tag(:div, helpers.simple_format(comment), class: "border-l-4 border-slate-300 pl-3 mb-3 last:mb-0")
      end
    )

    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Comments (#{@post.comments.length}):",
      value: comments_html,
      key: "post.comments"
    ))
  end

  def add_source_url_item(component)
    value = if @post.source_url.present?
      helpers.link_to(@post.source_url, @post.source_url, target: "_blank", rel: "noopener", class: "ff-link truncate block")
    else
      content_tag(:span, "None", class: "text-slate-500")
    end

    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Source URL:",
      value: value,
      key: "post.source_url"
    ))
  end

  def add_validation_errors_item(component)
    errors_html = if @post.validation_errors.is_a?(Array)
      content_tag(:ul, class: "list-disc list-inside mb-0 text-red-600") do
        safe_join(@post.validation_errors.map { |error| content_tag(:li, error) })
      end
    else
      content_tag(:div, @post.validation_errors, class: "text-red-600")
    end

    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Validation Errors:",
      value: errors_html,
      key: "post.validation_errors"
    ))
  end

  def add_uid_item(component)
    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "UID:",
      value: content_tag(:code, @post.uid, class: "text-sm"),
      key: "post.uid"
    ))
  end

  def add_freefeed_post_id_item(component)
    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "FreeFeed Post ID:",
      value: content_tag(:code, @post.freefeed_post_id, class: "text-sm"),
      key: "post.freefeed_post_id"
    ))
  end
end
