class PostDetailsComponent < ViewComponent::Base
  def initialize(post:)
    @post = post
  end

  def call
    render(ListComponent.new) do |list|
      add_feed_item(list)
      add_published_item(list)
      add_reposted_item(list) if @post.reposted_at
      add_source_url_item(list)
      add_validation_errors_item(list) if @post.validation_errors.present?
      add_uid_item(list)
      add_freefeed_post_id_item(list) if @post.freefeed_post_id.present?
    end
  end

  private

  def add_feed_item(component)
    component.with_item(StatListItemComponent.new(
      label: "Feed",
      value: helpers.link_to(@post.feed.display_name, @post.feed, class: "text-sky-600 underline underline-offset-4 transition hover:text-sky-500"),
      key: "post.feed"
    ))
  end

  def add_published_item(component)
    value = @post.published_at ? helpers.datetime_with_duration_tag(@post.published_at) : content_tag(:span, "Not published", class: "text-muted")
    component.with_item(StatListItemComponent.new(
      label: "Published",
      value: value,
      key: "post.published"
    ))
  end

  def add_reposted_item(component)
    component.with_item(StatListItemComponent.new(
      label: "Reposted",
      value: helpers.datetime_with_duration_tag(@post.reposted_at),
      key: "post.reposted"
    ))
  end

  def add_source_url_item(component)
    value = if @post.source_url.present?
      helpers.link_to(@post.source_url, @post.source_url, target: "_blank", rel: "noopener", class: "text-sky-600 underline underline-offset-4 transition hover:text-sky-500 truncate block")
    else
      content_tag(:span, "None", class: "text-muted")
    end

    component.with_item(StatListItemComponent.new(
      label: "Source URL",
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

    component.with_item(StatListItemComponent.new(
      label: "Validation Errors",
      value: errors_html,
      key: "post.validation_errors"
    ))
  end

  def add_uid_item(component)
    component.with_item(StatListItemComponent.new(
      label: "UID",
      value: content_tag(:code, @post.uid, class: "text-sm"),
      key: "post.uid"
    ))
  end

  def add_freefeed_post_id_item(component)
    url = @post.freefeed_url
    value = if url
      helpers.link_to(url, target: "_blank", rel: "noopener", class: "text-sky-600 underline underline-offset-4 transition hover:text-sky-500 inline-flex items-center gap-1") do
        safe_join([
          content_tag(:code, @post.freefeed_post_id, class: "text-sm"),
          helpers.icon("external-link", css_class: "size-3")
        ])
      end
    else
      content_tag(:code, @post.freefeed_post_id, class: "text-sm")
    end

    component.with_item(StatListItemComponent.new(
      label: "FreeFeed Post ID",
      value: value,
      key: "post.freefeed_post_id"
    ))
  end
end
