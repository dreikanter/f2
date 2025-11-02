class PostPreviewComponent < ViewComponent::Base
  def initialize(post_data:, index: nil)
    @post_data = post_data || {}
    @index = index
  end

  def title
    explicit_title = post_data["title"].presence
    return explicit_title if explicit_title

    preview = helpers.truncate(helpers.strip_tags(content), length: 80, omission: "...")
    preview.presence || default_title
  end

  def source_url
    post_data["source_url"].presence
  end

  def published_at
    @published_at ||= begin
      value = post_data["published_at"]
      value.present? ? Time.zone.parse(value) : nil
    rescue => error
      Rails.logger.warn("Feed preview post published_at parse error for #{value.inspect}: #{error.message}")
      nil
    end
  end

  def metadata_segments
    [].tap do |segments|
      segments << "UID #{post_data["uid"]}" if post_data["uid"].present?

      if published_at
        segments << "Published #{helpers.time_ago_in_words(published_at)} ago"
      end

      segments << "Attachments: #{valid_attachments.size}" if valid_attachments.any?
    end
  end

  def content
    post_data["content"].to_s
  end

  def formatted_content
    return if content.blank?

    helpers.content_tag(:div, helpers.simple_format(content), class: "rounded-lg bg-slate-50 text-slate-700")
  end

  def attachments?
    valid_attachments.any?
  end

  def attachments_list
    helpers.content_tag(:ul, class: "list-disc space-y-2 pl-4") do
      helpers.safe_join(valid_attachments.map { |attachment| attachment_list_item(attachment) })
    end
  end

  def card_id
    return unless index

    "feed-preview-post-#{index + 1}"
  end

  private

  attr_reader :post_data, :index

  def default_title
    index ? "Post #{index + 1}" : "Feed Preview Post"
  end

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

  def attachment_list_item(attachment)
    helpers.content_tag(:li) do
      fragments = [
        helpers.link_to(attachment[:url], attachment[:url], target: "_blank", rel: "noopener", class: "ff-link break-all")
      ]
      if attachment[:type]
        fragments << helpers.content_tag(:span, "(#{attachment[:type]})", class: "ml-2 text-xs text-slate-500")
      end
      helpers.safe_join(fragments)
    end
  end
end
