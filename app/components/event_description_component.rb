# Renders event descriptions with linked feed names
#
# Usage:
#   <%= render EventDescriptionComponent.new(event: event) %>
class EventDescriptionComponent < ViewComponent::Base
  attr_reader :event

  def initialize(event:)
    @event = event
  end

  def call
    html_description || fallback_description
  end

  private

  def html_description
    return unless I18n.exists?(description_key)

    I18n.t(
      description_key,
      subject_link: subject_link,
      feed_links: metadata_feed_links_html,
      message: escaped_message,
      stage: stage
    ).html_safe
  end

  def fallback_description
    (event.message.present? ? escaped_message : default_description).html_safe
  end

  def description_key
    "events.#{event_type}.description_html"
  end

  # resend.email.email_bounced → resend_email_bounced
  def event_type
    @event_type ||= event.type.sub("resend.email.", "resend_").underscore.tr(".", "_")
  end

  def subject_link
    case event.subject
    when Feed
      helpers.link_to(event.subject.name, helpers.feed_path(event.subject), class: "ff-link")
    when AccessToken
      helpers.link_to(event.subject.name, helpers.settings_access_tokens_path, class: "ff-link")
    when Post
      helpers.link_to("Post", helpers.post_path(event.subject), class: "ff-link")
    else
      ""
    end
  end

  def escaped_message
    @escaped_message ||= ERB::Util.html_escape(event.message.to_s)
  end

  def stage
    raw_stage = event.metadata.dig("error", "stage")
    raw_stage.to_s.humanize(capitalize: false)
  end

  def default_description
    I18n.t("events.#{event.type}.name", default: event.type.humanize)
  end

  def metadata_feed_links_html
    return "" if disabled_feed_ids.blank?

    links = disabled_feeds.map do |feed|
      helpers.link_to(feed.name, helpers.feed_path(feed), class: "ff-link")
    end

    linked_feeds = helpers.safe_join(links, ", ")
    deleted_feeds_count = disabled_feed_ids.size - disabled_feeds.size

    if deleted_feeds_count.positive?
      deleted_feeds_note = helpers.pluralize(deleted_feeds_count, "deleted feeds")
      [linked_feeds, deleted_feeds_note].compact_blank.join(" and ")
    else
      linked_feeds
    end
  end

  def disabled_feeds
    @disabled_feeds ||= Feed.where(id: disabled_feed_ids)
  end

  def disabled_feed_ids
    @disabled_feed_ids ||= Array(event.metadata["disabled_feed_ids"])
  end
end
