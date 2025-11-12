# Renders event descriptions with linked feed names
#
# Usage:
#   <%= render EventDescriptionComponent.new(event: event) %>
class EventDescriptionComponent < ViewComponent::Base
  def initialize(event:)
    @event = event
  end

  def before_render
    @subject_link = compute_subject_link
    @metadata_feed_links = compute_metadata_feed_links
    @escaped_message = compute_escaped_message
    @default_description = compute_default_description
  end

  def call
    description = if I18n.exists?("events.#{event_type}.description")
      I18n.t(
        "events.#{event_type}.description",
        subject_link: @subject_link,
        feed_links: @metadata_feed_links,
        message: @escaped_message
      )
    else
      @event.message.present? ? @escaped_message : @default_description
    end

    description.html_safe
  end

  private

  def event_type
    @event.type.underscore
  end

  def compute_subject_link
    return "" unless @event.subject

    case @event.subject
    when Feed
      helpers.link_to(@event.subject.name, helpers.feed_path(@event.subject))
    when AccessToken
      helpers.link_to(@event.subject.name, helpers.settings_access_tokens_path)
    when Post
      helpers.link_to("Post", helpers.post_path(@event.subject))
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

  def compute_metadata_feed_links
    return "" if metadata_feeds.empty?

    links = metadata_feeds.map { |feed| helpers.link_to(feed.name, helpers.feed_path(feed)) }
    helpers.safe_join(links, ", ")
  end

  def compute_escaped_message
    ERB::Util.html_escape(@event.message || "")
  end

  def compute_default_description
    I18n.t("events.#{@event.type}.name", default: @event.type.humanize)
  end
end
