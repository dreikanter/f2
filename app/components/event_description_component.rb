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
    @stage = build_stage
    @metadata_feed_links_html = build_metadata_feed_links_html
  end

  def call
    if I18n.exists?("events.#{event_type}.description_html")
      I18n.t(
        "events.#{event_type}.description_html",
        subject_link: @subject_link,
        feed_links: @metadata_feed_links_html,
        message: @escaped_message,
        stage: @stage
      ).html_safe
    else
      (@event.message.present? ? @escaped_message : @default_description).html_safe
    end
  end

  private

  # Handle resend.email.* events by removing redundant .email. segment
  # resend.email.email_bounced -> resend_email_bounced
  def event_type
    @event.type.sub("resend.email.", "resend_").underscore.tr(".", "_")
  end

  def build_subject_link
    case @event.subject
    when Feed
      helpers.link_to(@event.subject.name, helpers.feed_path(@event.subject), class: "ff-link")
    when AccessToken
      helpers.link_to(@event.subject.name, helpers.settings_access_tokens_path, class: "ff-link")
    when Post
      helpers.link_to("Post", helpers.post_path(@event.subject), class: "ff-link")
    else
      ""
    end
  end

  def build_escaped_message
    ERB::Util.html_escape(@event.message || "").html_safe
  end

  def build_stage
    stage = @event.metadata.dig("error", "stage")
    return "" unless stage

    stage.to_s.humanize(capitalize: false)
  end

  def build_default_description
    I18n.t("events.#{@event.type}.name", default: @event.type.humanize)
  end

  def build_metadata_feed_links_html
    feeds = disabled_feeds
    links = feeds.map { helpers.link_to(_1.name, helpers.feed_path(_1), class: "ff-link") }
    linked_feeds = helpers.safe_join(links, ", ")
    deleted_feeds_count = disabled_feed_ids.count - feeds.count

    if deleted_feeds_count.positive?
      deleted_feeds_note = "#{helpers.pluralize(deleted_feeds_count, 'deleted feeds')}"
      [linked_feeds, deleted_feeds_note].compact_blank.join(" and ")
    else
      linked_feeds
    end
  end

  def disabled_feeds
    disabled_feed_ids.empty? ? [] : Feed.where(id: disabled_feed_ids)
  end

  def disabled_feed_ids
    @disabled_feed_ids ||= @event.metadata["disabled_feed_ids"] || []
  end
end
