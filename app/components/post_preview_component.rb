class PostPreviewComponent < ViewComponent::Base
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
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError => error
      Rails.error.report(error, context: { component: "feed_preview", value: value.inspect })
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
    attachments.any?
  end

  def comments?
    comments.any?
  end

  def comments
    @comments ||= Array(post_data["comments"]).filter_map { |comment| comment.to_s.presence }
  end

  def attachments
    @attachments ||= Array(post_data["attachments"]).compact_blank
  end

  def card_id
    return unless index

    "feed-preview-post-#{index + 1}"
  end

  private

  attr_reader :post_data, :index
end
