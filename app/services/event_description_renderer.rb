# Renders event descriptions with linked feed names
#
# Generates HTML descriptions for events by:
# - Resolving feed references (from subject or metadata)
# - Creating safe HTML links to feeds
# - Using i18n templates with interpolation
# - Supporting both single and multiple feed references
#
# Usage:
#   renderer = EventDescriptionRenderer.new(event)
#   html = renderer.render # => ActiveSupport::SafeBuffer with HTML
class EventDescriptionRenderer
  include ActionView::Helpers::UrlHelper
  include ActionView::Helpers::TagHelper
  include Rails.application.routes.url_helpers

  def initialize(event)
    @event = event
  end

  # Provide default_url_options for URL helpers
  def default_url_options
    Rails.application.config.action_mailer.default_url_options || {}
  end

  def render
    feed_count = feeds.count
    metadata_feed_count = feeds_from_metadata.count
    total_count = feed_count + metadata_feed_count

    # Default to count: 1 for non-feed events to use the "one" form
    count = total_count.positive? ? total_count : 1

    description = I18n.t(
      "events.descriptions.#{event_type}",
      count: count,
      feed_link: single_feed_link,
      feed_links: multiple_feed_links,
      error: error_message,
      default: fallback_message
    )

    description.html_safe
  end

  private

  attr_reader :event

  def event_type
    @event.type.underscore
  end

  def feeds
    @feeds ||= begin
      if @event.subject_type == "Feed" && @event.subject
        [@event.subject]
      else
        []
      end
    end
  end

  def feeds_from_metadata
    @feeds_from_metadata ||= begin
      feed_ids = @event.metadata["disabled_feed_ids"] || []
      return [] if feed_ids.empty?

      Feed.where(id: feed_ids).order(:name)
    end
  end

  def all_feeds
    @all_feeds ||= feeds + feeds_from_metadata.to_a
  end

  def single_feed_link
    feed = all_feeds.first
    return "" unless feed

    %(<a href="/feeds/#{feed.id}">#{ERB::Util.html_escape(feed.name)}</a>).html_safe
  end

  def multiple_feed_links
    return "" if all_feeds.empty?

    links = all_feeds.map do |feed|
      %(<a href="/feeds/#{feed.id}">#{ERB::Util.html_escape(feed.name)}</a>)
    end
    links.join(", ").html_safe
  end

  def error_message
    @event.metadata["error_message"] || ""
  end

  def fallback_message
    # Fall back to stored message or type name
    if @event.message.present?
      ERB::Util.html_escape(@event.message)
    else
      I18n.t("events.types.#{@event.type}", default: @event.type.humanize)
    end
  end
end
