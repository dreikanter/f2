module IdentifierHelper
  UUID_SUFFIX_LENGTH = 5
  UUID_LINK_CLASSES = "font-mono underline underline-offset-2 transition hover:text-heading".freeze
  UUID_TEXT_CLASSES = "font-mono".freeze

  EVENT_SUBJECT_MODELS = {
    "Feed" => Feed,
    "User" => User,
    "Event" => Event,
    "AccessToken" => AccessToken,
    "AiCredential" => AiCredential,
    "SearchCredential" => SearchCredential
  }.freeze

  def short_uuid(value)
    value.to_s.last(UUID_SUFFIX_LENGTH)
  end

  def uuid_label(value, prefix: nil)
    [prefix, short_uuid(value)].compact_blank.join(" ")
  end

  def uuid_reference(value, path: nil, prefix: nil, link_class: UUID_LINK_CLASSES, text_class: UUID_TEXT_CLASSES, **html_options)
    html_options[:title] ||= value.to_s
    html_options[:class] ||= path ? link_class : text_class
    label = uuid_label(value, prefix: prefix)

    path ? link_to(label, path, **html_options) : tag.span(label, **html_options)
  end

  def admin_event_subject_path(subject)
    case subject
    when Feed
      admin_feed_path(subject)
    when User
      admin_user_path(subject)
    when Event
      admin_event_path(subject)
    when AccessToken
      access_token_path(subject)
    when AiCredential
      ai_credential_path(subject)
    when SearchCredential
      search_credential_path(subject)
    end
  end

  def admin_event_filter_reference_path(key, value, filter:)
    case key.to_s
    when "user_id"
      user = User.find_by(id: value)
      admin_user_path(user) if user
    when "subject_id"
      subject_type = filter[:subject_type] || filter["subject_type"]
      model = EVENT_SUBJECT_MODELS[subject_type]
      subject = model&.find_by(id: value)
      admin_event_subject_path(subject) if subject
    end
  end
end
