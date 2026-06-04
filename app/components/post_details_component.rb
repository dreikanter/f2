class PostDetailsComponent < ViewComponent::Base
  def initialize(post:)
    @post = post
  end

  def call
    render(ListComponent.new) do |list|
      add_feed_item(list)
      add_published_item(list)
      add_attachments_item(list) if @post.attachment_urls.present?
      add_comments_item(list) if @post.comments.present?
      add_source_url_item(list)
      add_validation_errors_item(list) if @post.validation_errors.present?
      add_uid_item(list)
      add_freefeed_post_id_item(list) if @post.freefeed_post_id.present?
    end
  end

  private

  def add_feed_item(component)
    component.with_item(ListComponent::StatItemComponent.new(
      label: "Feed",
      value: helpers.link_to(@post.feed.display_name, @post.feed, class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500"),
      key: "post.feed"
    ))
  end

  def add_published_item(component)
    value = @post.published_at ? helpers.datetime_with_duration_tag(@post.published_at) : content_tag(:span, "Not published", class: "text-slate-500")
    component.with_item(ListComponent::StatItemComponent.new(
      label: "Published",
      value: value,
      key: "post.published"
    ))
  end

  def add_attachments_item(component)
    attachments_html = safe_join(
      @post.attachment_urls.map do |url|
        filename = extract_filename(url)
        helpers.link_to(url, target: "_blank", rel: "noopener", class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500 inline-flex items-center") do
          safe_join([
            helpers.icon("file-image", css_class: "size-4"),
            content_tag(:span, filename, class: "sr-only")
          ])
        end
      end,
      " "
    )

    component.with_item(ListComponent::StatItemComponent.new(
      label: "Attachments (#{@post.attachment_urls.length})",
      value: attachments_html,
      key: "post.attachments"
    ))
  end

  def extract_filename(url)
    uri = URI.parse(url)
    filename = File.basename(uri.path)
    filename.presence || "Attachment"
  rescue URI::InvalidURIError
    "Attachment"
  end

  def add_comments_item(component)
    comments_html = safe_join(
      @post.comments.map do |comment|
        content_tag(:div, helpers.simple_format(comment), class: "border-l-4 border-slate-300 pl-3 mb-3 last:mb-0")
      end
    )

    component.with_item(ListComponent::StatItemComponent.new(
      label: "Comments (#{@post.comments.length})",
      value: comments_html,
      key: "post.comments"
    ))
  end

  def add_source_url_item(component)
    value = if @post.source_url.present?
      helpers.link_to(@post.source_url, @post.source_url, target: "_blank", rel: "noopener", class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500 truncate block")
    else
      content_tag(:span, "None", class: "text-slate-500")
    end

    component.with_item(ListComponent::StatItemComponent.new(
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

    component.with_item(ListComponent::StatItemComponent.new(
      label: "Validation Errors",
      value: errors_html,
      key: "post.validation_errors"
    ))
  end

  def add_uid_item(component)
    component.with_item(ListComponent::StatItemComponent.new(
      label: "UID",
      value: content_tag(:code, @post.uid, class: "text-sm"),
      key: "post.uid"
    ))
  end

  def add_freefeed_post_id_item(component)
    value = if (url = freefeed_post_url)
      helpers.link_to(url, target: "_blank", rel: "noopener", class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500 inline-flex items-center gap-1") do
        safe_join([
          content_tag(:code, @post.freefeed_post_id, class: "text-sm"),
          helpers.icon("external-link", css_class: "size-3")
        ])
      end
    else
      content_tag(:code, @post.freefeed_post_id, class: "text-sm")
    end

    component.with_item(ListComponent::StatItemComponent.new(
      label: "FreeFeed Post ID",
      value: value,
      key: "post.freefeed_post_id"
    ))
  end

  def freefeed_post_url
    feed = @post.feed
    token = feed&.access_token
    return unless token && feed.target_group.present?

    "#{token.host}/#{feed.target_group}/#{@post.freefeed_post_id}"
  end
end
