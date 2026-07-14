module IdentifierHelper
  UUID_SUFFIX_LENGTH = 5

  EVENT_SUBJECT_MODELS = {
    "Feed" => Feed,
    "User" => User,
    "Event" => Event,
    "AccessToken" => AccessToken,
    "AiCredential" => AiCredential,
    "SearchCredential" => SearchCredential
  }.freeze

  def short_ref(value)
    value.to_s.last(UUID_SUFFIX_LENGTH)
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
