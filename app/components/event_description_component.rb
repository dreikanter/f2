# Renders an event's human-readable description from its i18n translation.
#
# Build instances through `.for`, which picks a type-specific subclass when one
# exists (e.g. feed refreshes append their imported posts count):
#
#   <%= render EventDescriptionComponent.for(event) %>
class EventDescriptionComponent < ViewComponent::Base
  attr_reader :event

  # Maps event types to the subclass that renders them. Types without an entry
  # fall back to this base component, which renders the plain description.
  SUBCLASSES = {
    "feed_refresh" => "FeedRefreshDescriptionComponent",
    "feed_auto_disabled" => "FeedAutoDisabledDescriptionComponent",
    "feed_target_group_unavailable" => "FeedTargetGroupUnavailableDescriptionComponent"
  }.freeze

  def self.for(event, admin: false)
    klass = SUBCLASSES[event.type]&.constantize || self
    klass.new(event: event, admin: admin)
  end

  def initialize(event:, admin: false)
    @event = event
    @admin = admin
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
      helpers.link_to(event.subject.display_name, feed_link_path(event.subject), class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500")
    when AccessToken
      helpers.link_to(event.subject.name, helpers.access_tokens_path, class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500")
    when Post
      helpers.link_to("Post", helpers.post_path(event.subject), class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500")
    when AiCredential
      helpers.link_to(event.subject.display_name, helpers.ai_credential_path(event.subject), class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500")
    else
      ""
    end
  end

  # Admin event pages link feeds to the operator-facing feed page so admins can
  # inspect any user's feed; user-facing pages stay on the owner route.
  def feed_link_path(feed)
    @admin ? helpers.admin_feed_path(feed) : helpers.feed_path(feed)
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
      helpers.link_to(feed.display_name, feed_link_path(feed), class: "font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500")
    end

    linked_feeds = helpers.safe_join(links, ", ")
    deleted_feeds_count = disabled_feed_ids.size - disabled_feeds.size

    if deleted_feeds_count.positive?
      deleted_feeds_note = helpers.pluralize(deleted_feeds_count, "deleted feeds")
      helpers.safe_join([linked_feeds.presence, deleted_feeds_note].compact_blank, " and ")
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
