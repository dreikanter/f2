class PostDetailsComponent < ViewComponent::Base
  def initialize(post:)
    @post = post
  end

  def call
    component = ListGroupComponent.new

    add_feed_item(component)
    add_content_item(component)
    add_published_item(component)
    add_status_item(component)
    add_attachments_item(component) if @post.attachment_urls.present?
    add_comments_item(component) if @post.comments.present?
    add_external_links_item(component)
    add_validation_errors_item(component) if @post.validation_errors.present?
    add_post_id_item(component)
    add_uid_item(component)
    add_feed_entry_id_item(component)
    add_freefeed_post_id_item(component) if @post.freefeed_post_id.present?
    add_created_at_item(component)
    add_updated_at_item(component)

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

  def add_content_item(component)
    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Content:",
      value: content_tag(:div, helpers.simple_format(@post.content), class: "text-slate-900"),
      key: "post.content"
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

  def add_status_item(component)
    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Status:",
      value: @post.status.capitalize,
      key: "post.status"
    ))
  end

  def add_attachments_item(component)
    attachments_html = safe_join(
      @post.attachment_urls.map do |url|
        helpers.link_to(url, target: "_blank", rel: "noopener", class: "ff-link inline-flex items-center gap-1") do
          safe_join([helpers.icon("file-earmark-image", aria_hidden: true), url])
        end
      end,
      content_tag(:br)
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

  def add_external_links_item(component)
    links = []

    if @post.freefeed_post_id.present? && @post.feed.access_token.present? && @post.feed.target_group.present?
      freefeed_url = "#{@post.feed.access_token.host}/#{@post.feed.target_group}/#{@post.freefeed_post_id}"
      links << helpers.link_to("View on FreeFeed", freefeed_url, target: "_blank", rel: "noopener", class: "ff-link")
    end

    if @post.source_url.present?
      links << helpers.link_to("View Original Source", @post.source_url, target: "_blank", rel: "noopener", class: "ff-link")
    end

    value = if links.any?
      safe_join(links, " #{content_tag(:span, '|', class: 'text-slate-300')} ".html_safe)
    else
      content_tag(:span, "No external links available", class: "text-slate-500")
    end

    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "External Links:",
      value: value,
      key: "post.external_links"
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

  def add_post_id_item(component)
    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Post ID:",
      value: content_tag(:code, @post.id, class: "text-sm"),
      key: "post.id"
    ))
  end

  def add_uid_item(component)
    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "UID:",
      value: content_tag(:code, @post.uid, class: "text-sm"),
      key: "post.uid"
    ))
  end

  def add_feed_entry_id_item(component)
    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Feed Entry ID:",
      value: content_tag(:code, @post.feed_entry_id, class: "text-sm"),
      key: "post.feed_entry_id"
    ))
  end

  def add_freefeed_post_id_item(component)
    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "FreeFeed Post ID:",
      value: content_tag(:code, @post.freefeed_post_id, class: "text-sm"),
      key: "post.freefeed_post_id"
    ))
  end

  def add_created_at_item(component)
    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Created:",
      value: helpers.long_time_tag(@post.created_at),
      key: "post.created_at"
    ))
  end

  def add_updated_at_item(component)
    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Updated:",
      value: helpers.long_time_tag(@post.updated_at),
      key: "post.updated_at"
    ))
  end
end
