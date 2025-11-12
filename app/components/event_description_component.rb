# Renders event descriptions with linked feed names
#
# Generates HTML descriptions for events by:
# - Resolving feed references (from subject or metadata)
# - Creating safe HTML links to feeds
# - Using i18n templates with interpolation
# - Supporting both single and multiple feed references
#
# Usage:
#   <%= render EventDescriptionComponent.new(event: event) %>
class EventDescriptionComponent < ViewComponent::Base
  def initialize(event:)
    @event = event
  end

  def call
    # Count is based on metadata feeds only (e.g., disabled_feed_ids)
    # Use stored count if available (preserves accurate count even if feeds are deleted)
    count = if @event.metadata["disabled_count"]
      @event.metadata["disabled_count"]
    else
      metadata_feeds.count.positive? ? metadata_feeds.count : 1
    end

    description = I18n.t(
      "events.#{event_type}.description",
      count: count,
      subject_link: subject_link,
      feed_link: single_metadata_feed_link,
      feed_links: multiple_metadata_feed_links,
      message: escaped_message,
      default: fallback_message
    )

    description.html_safe
  end

  private

  def event_type
    @event.type.underscore
  end

  def subject_link
    return "" unless @event.subject

    case @event.subject
    when Feed
      helpers.link_to(@event.subject.name, helpers.feed_path(@event.subject))
    when AccessToken
      helpers.link_to(@event.subject.name, helpers.settings_access_tokens_path)
    when Post
      helpers.link_to("Post", helpers.post_path(@event.subject))
    when User
      ERB::Util.html_escape(@event.subject.email_address)
    else
      ""
    end
  end

  def metadata_feeds
    @metadata_feeds ||= begin
      feed_ids = @event.metadata["disabled_feed_ids"] || []
      return [] if feed_ids.empty?

      Feed.where(id: feed_ids).order(:name)
    end
  end

  def single_metadata_feed_link
    feed = metadata_feeds.first
    return "" unless feed

    helpers.link_to(feed.name, helpers.feed_path(feed))
  end

  def multiple_metadata_feed_links
    return "" if metadata_feeds.empty?

    links = metadata_feeds.map { |feed| helpers.link_to(feed.name, helpers.feed_path(feed)) }
    helpers.safe_join(links, ", ")
  end

  def escaped_message
    ERB::Util.html_escape(@event.message || "")
  end

  def fallback_message
    # Fall back to stored message or event name
    if @event.message.present?
      ERB::Util.html_escape(@event.message)
    else
      I18n.t("events.#{@event.type}.name", default: @event.type.humanize)
    end
  end
end
