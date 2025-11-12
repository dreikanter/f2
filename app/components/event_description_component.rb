# Renders event descriptions with linked feed names
#
# Usage:
#   <%= render EventDescriptionComponent.new(event: event) %>
class EventDescriptionComponent < ViewComponent::Base
  def initialize(event:)
    @event = event
  end

  def before_render
    @subject_link = build_subject_link
    @escaped_message = build_escaped_message
    @default_description = build_default_description

    # Build metadata feed links HTML
    feeds = metadata_feeds
    disabled_count = @event.metadata["disabled_count"]

    @metadata_feed_links_html = if disabled_count && disabled_count > 0
      count_text = "#{disabled_count} #{'feed'.pluralize(disabled_count)}"
      if feeds.empty?
        # All feeds deleted - show just the count
        count_text
      elsif feeds.length < disabled_count
        # Some feeds deleted - show count and remaining feed names
        links = feeds.map { |feed| helpers.link_to(feed.name, helpers.feed_path(feed)) }
        "#{count_text}: #{helpers.safe_join(links, ', ')}"
      else
        # All feeds still exist - show just the feed links
        links = feeds.map { |feed| helpers.link_to(feed.name, helpers.feed_path(feed)) }
        helpers.safe_join(links, ", ")
      end
    elsif feeds.any?
      # No count stored, just show the feed links
      links = feeds.map { |feed| helpers.link_to(feed.name, helpers.feed_path(feed)) }
      helpers.safe_join(links, ", ")
    else
      ""
    end
  end

  def call
    description = if I18n.exists?("events.#{event_type}.description")
      I18n.t(
        "events.#{event_type}.description",
        subject_link: @subject_link,
        feed_links: @metadata_feed_links_html,
        message: @escaped_message
      )
    else
      @event.message.present? ? @escaped_message : @default_description
    end

    description.html_safe
  end

  private

  def event_type
    @event.type.underscore.tr(".", "_")
  end

  def build_subject_link
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

  def build_escaped_message
    ERB::Util.html_escape(@event.message || "")
  end

  def build_default_description
    I18n.t("events.#{@event.type}.name", default: @event.type.humanize)
  end
end
