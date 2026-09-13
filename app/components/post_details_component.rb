class PostDetailsComponent < ViewComponent::Base
  def initialize(post:)
    @post = post
  end

  def call
    render(DescriptionListComponent.new) do |list|
      items.each { |item| list.with_item(item) }
    end
  end

  private

  def items
    [
      feed_item,
      published_item,
      (reposted_item if @post.reposted_at),
      source_url_item,
      (validation_errors_item if @post.validation_errors.present?),
      uid_item,
      (freefeed_post_id_item if @post.freefeed_post_id.present?)
    ].compact
  end

  def feed_item
    StatListItemComponent.new(
      label: "Feed",
      value: helpers.link_to(@post.feed.display_name, @post.feed, class: helpers.text_link_classes),
      key: "post.feed"
    )
  end

  def published_item
    value = @post.published_at ? helpers.datetime_with_duration_tag(@post.published_at) : content_tag(:span, "Not published", class: "text-muted")
    StatListItemComponent.new(
      label: "Published",
      value: value,
      key: "post.published"
    )
  end

  def reposted_item
    StatListItemComponent.new(
      label: "Reposted",
      value: helpers.datetime_with_duration_tag(@post.reposted_at),
      key: "post.reposted"
    )
  end

  def source_url_item
    value = if @post.source_url.present?
      helpers.link_to(@post.source_url, @post.source_url, target: "_blank", rel: "noopener", title: @post.source_url, class: helpers.text_link_classes)
    else
      content_tag(:span, "None", class: "text-muted")
    end

    StatListItemComponent.new(
      label: "Source URL",
      value: value,
      key: "post.source_url",
      truncate: @post.source_url.present?
    )
  end

  def validation_errors_item
    errors_html = if @post.validation_errors.is_a?(Array)
      content_tag(:ul, class: "list-disc list-inside mb-0 text-danger") do
        safe_join(@post.validation_errors.map { |error| content_tag(:li, error) })
      end
    else
      content_tag(:div, @post.validation_errors, class: "text-danger")
    end

    StatListItemComponent.new(
      label: "Validation Errors",
      value: errors_html,
      key: "post.validation_errors"
    )
  end

  def uid_item
    StatListItemComponent.new(
      label: "UID",
      value: content_tag(:code, @post.uid, class: "text-sm", title: @post.uid),
      key: "post.uid",
      truncate: true
    )
  end

  def freefeed_post_id_item
    url = @post.freefeed_post_url
    value = if url
      helpers.link_to(url, target: "_blank", rel: "noopener", class: class_names(helpers.text_link_classes, "inline-flex items-center gap-1")) do
        safe_join([
          content_tag(:code, @post.freefeed_post_id, class: "text-sm"),
          helpers.icon("external-link", css_class: "size-3")
        ])
      end
    else
      content_tag(:code, @post.freefeed_post_id, class: "text-sm")
    end

    StatListItemComponent.new(
      label: "FreeFeed Post ID",
      value: value,
      key: "post.freefeed_post_id",
      truncate: true
    )
  end
end
