class PostPreviewComponent < ViewComponent::Base
  IMAGE_EXTENSIONS = %w[jpg jpeg png gif webp avif bmp svg].freeze

  def initialize(post_data:, index: nil)
    @post_data = post_data || {}
    @index = index
  end

  def uid
    post_data["uid"].presence
  end

  def source_url
    post_data["source_url"].presence
  end

  def published_at
    @published_at ||= begin
      value = post_data["published_at"]
      value.present? ? Time.zone.parse(value) : nil
    rescue => error
      Rails.error.report(error, context: { component: self.class.name, published_at: value })
      nil
    end
  end

  def published_compact
    return unless published_at

    diff = (Time.zone.now - published_at).abs.to_i
    if diff < 60
      "#{diff}s"
    elsif diff < 3_600
      "#{diff / 60}m"
    elsif diff < 86_400
      "#{diff / 3_600}h"
    elsif diff < 604_800
      "#{diff / 86_400}d"
    elsif diff < 2_592_000
      "#{diff / 604_800}w"
    else
      helpers.l(published_at.to_date)
    end
  end

  def post_content
    post_data["content"].to_s
  end

  def formatted_content
    return if post_content.blank?

    helpers.content_tag(:div, helpers.format_post_content(post_content), class: "rounded-lg text-heading")
  end

  def attachments?
    valid_attachments.any?
  end

  def image_attachments
    @image_attachments ||= valid_attachments.select { |attachment| image_attachment?(attachment) }
  end

  def other_attachments
    @other_attachments ||= valid_attachments.reject { |attachment| image_attachment?(attachment) }
  end

  def thumbnail_url(url)
    ImgproxyUrl.preview(url)
  end

  def thumbnail_srcset(url)
    ImgproxyUrl.preview_srcset(url)
  end

  def thumbnail_size
    ImgproxyUrl::THUMBNAIL_SIZE
  end

  def other_attachments_list
    helpers.content_tag(:ul, class: "list-disc space-y-2 pl-4") do
      helpers.safe_join(other_attachments.map { |attachment| attachment_list_item(attachment) })
    end
  end

  def card_id
    return unless index

    "feed-preview-post-#{index + 1}"
  end

  private

  attr_reader :post_data, :index

  def valid_attachments
    @valid_attachments ||= raw_attachments.filter_map do |attachment|
      url = attachment_url(attachment)
      next if url.blank?

      { url: url, type: attachment_type(attachment) }
    end
  end

  def raw_attachments
    Array(post_data["attachments"]).compact_blank
  end

  def attachment_url(attachment)
    attachment.is_a?(Hash) ? attachment["url"] : attachment
  end

  def attachment_type(attachment)
    attachment.is_a?(Hash) ? attachment["type"].presence : nil
  end

  # Treat an attachment as an image when its declared type says so, or — when no
  # type is given — when the URL ends in a known image extension. Only images get
  # a thumbnail; everything else stays a link to avoid broken previews.
  def image_attachment?(attachment)
    type = attachment[:type].to_s.downcase
    return type.start_with?("image") if type.present?

    extension = File.extname(URI.parse(attachment[:url]).path).delete(".").downcase
    IMAGE_EXTENSIONS.include?(extension)
  rescue URI::InvalidURIError
    false
  end

  def attachment_list_item(attachment)
    helpers.content_tag(:li) do
      fragments = [
        helpers.link_to(attachment[:url], attachment[:url], target: "_blank", rel: "noopener", class: "font-medium text-brand underline underline-offset-4 transition hover:text-brand-hover break-all")
      ]
      if attachment[:type]
        fragments << helpers.content_tag(:span, "(#{attachment[:type]})", class: "ml-2 text-xs text-muted")
      end
      helpers.safe_join(fragments)
    end
  end
end
