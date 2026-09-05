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
    "feed_preview" => "FeedPreviewDescriptionComponent",
    "feed_refresh" => "FeedRefreshDescriptionComponent",
    "feed_auto_disabled" => "FeedAutoDisabledDescriptionComponent",
    "feed_target_group_unavailable" => "FeedTargetGroupUnavailableDescriptionComponent",
    "feed_ai_credential_removed" => "FeedCredentialRemovedDescriptionComponent",
    "feed_search_credential_removed" => "FeedCredentialRemovedDescriptionComponent"
  }.freeze

  # Shared styling for every entity link a description interpolates, so the
  # subject and the metadata feed list read as the same kind of link.
  ENTITY_LINK_CLASSES = "font-medium text-brand underline underline-offset-4 transition hover:text-brand-hover".freeze

  def self.for(event)
    klass = SUBCLASSES[event.type]&.constantize || self
    klass.new(event: event)
  end

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

  # A stored message is raw operational text that doesn't say what produced it,
  # so the event name leads it.
  def fallback_description
    return ERB::Util.html_escape(default_description) if event.message.blank?

    helpers.safe_join([helpers.tag.span(default_description, class: "font-medium"), helpers.middot, escaped_message])
  end

  def description_key
    "events.#{event_type}.description_html"
  end

  # resend.email.email_bounced → resend_email_bounced
  def event_type
    @event_type ||= event.type.sub("resend.email.", "resend_").underscore.tr(".", "_")
  end

  def subject_link
    subject = event.subject

    case subject
    when Feed then entity_link(subject.display_name, feed_link_path(subject))
    when AccessToken then entity_link(subject.name, access_token_link_path(subject))
    when Post then entity_link("Post", helpers.post_path(subject))
    when AiCredential then entity_link(subject.display_name, ai_credential_link_path(subject))
    when SearchCredential then entity_link(subject.display_name, search_credential_link_path(subject))
    else orphaned_subject_placeholder
    end
  end

  def entity_link(label, path)
    helpers.link_to(label, path, class: ENTITY_LINK_CLASSES)
  end

  # A recorded subject_type with no loadable subject means the record was
  # deleted (credentials outlive their events' subjects); descriptions that
  # interpolate %{subject_link} need a stand-in, not a hole in the sentence.
  def orphaned_subject_placeholder
    event.subject.nil? && event.subject_type.present? ? "(removed)" : ""
  end

  # Subjects link to the owner-facing pages. Admin::EventDescriptionComponent
  # overrides these (via Admin::EventEntityLinks) to point at the
  # operator-facing pages instead.
  def feed_link_path(feed)
    helpers.feed_path(feed)
  end

  # Owners manage tokens from the list page, so descriptions send them there.
  def access_token_link_path(_access_token)
    helpers.access_tokens_path
  end

  def ai_credential_link_path(credential)
    helpers.ai_credential_path(credential)
  end

  def search_credential_link_path(credential)
    helpers.search_credential_path(credential)
  end

  def escaped_message
    @escaped_message ||= ERB::Util.html_escape(event.message.to_s)
  end

  def stage
    raw_stage = event.metadata.dig("error", "stage")
    raw_stage.to_s.humanize(capitalize: false)
  end

  def default_description
    I18n.t("events.#{event_type}.name", default: event.type.tr(".", " ").humanize)
  end

  def metadata_feed_links_html
    return "" if disabled_feed_ids.blank?

    links = disabled_feeds.map { |feed| entity_link(feed.display_name, feed_link_path(feed)) }

    linked_feeds = helpers.safe_join(links, ", ")
    deleted_feeds_count = disabled_feed_ids.size - disabled_feeds.size

    if deleted_feeds_count.positive?
      deleted_feeds_note = helpers.pluralize(deleted_feeds_count, "deleted feed")
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
