class PostAttachmentsComponent < ViewComponent::Base
  CARD_CLASSES = "overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm p-4".freeze

  def initialize(post:)
    @post = post
  end

  def render?
    @post.attachment_urls.present?
  end

  def call
    content_tag(:div, class: CARD_CLASSES, data: { key: "post.attachments" }) do
      safe_join([
        content_tag(:h2, "Attachments (#{@post.attachment_urls.length})", class: "text-lg font-semibold text-slate-900 mb-3"),
        content_tag(:div, attachments_html, class: "flex flex-wrap gap-3")
      ])
    end
  end

  private

  def attachments_html
    safe_join(
      @post.attachment_urls.map do |url|
        filename = extract_filename(url)
        helpers.link_to(url, target: "_blank", rel: "noopener", class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500 inline-flex items-center") do
          safe_join([
            helpers.icon("file-image", css_class: "size-4"),
            content_tag(:span, filename, class: "sr-only")
          ])
        end
      end
    )
  end

  def extract_filename(url)
    uri = URI.parse(url)
    filename = File.basename(uri.path)
    filename.presence || "Attachment"
  rescue URI::InvalidURIError
    "Attachment"
  end
end
