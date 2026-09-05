# The "AI Settings" section of the feed form: AI and search credentials plus
# the model select, or the credential gate when either required key is missing.
class FeedAiSettingsComponent < ViewComponent::Base
  def initialize(feed:, form:)
    @feed = feed
    @form = form
  end

  # Shown only for AI-backed profiles. The section is always rendered (so the
  # Stimulus controller can reveal it when the user switches to an AI candidate
  # mid-form); this drives the initial hidden state and the disabled selects.
  def section_visible?
    @feed.feed_profile_present? && FeedProfile.depends_on_ai?(@feed.feed_profile_key)
  end

  def active_credentials
    @active_credentials ||= @feed.user.ai_credentials.active.order(:display_name)
  end

  def selectable_credentials
    @selectable_credentials ||= active_credentials.select { |credential| models_by_credential.key?(credential.id.to_s) }
  end

  def credentials?
    selectable_credentials.any?
  end

  def active_search_credentials
    @active_search_credentials ||= @feed.user.search_credentials.active.order(:display_name)
  end

  def search_credentials?
    active_search_credentials.any?
  end

  def credential_setup_complete?
    credentials? && search_credentials?
  end

  def models_by_credential
    @models_by_credential ||= active_credentials.to_h do |credential|
      models = credential.supported_models
                         .map { |model| { "id" => model["id"], "name" => model["name"].presence || model["id"] } }
      if credential.id == @feed.ai_credential_id && @feed.ai_model.present? && models.none? { |model| model["id"] == @feed.ai_model }
        models << { "id" => @feed.ai_model, "name" => "#{@feed.ai_model} (saved model)" }
      end
      [credential.id.to_s, models.sort_by { |model| model["name"].to_s.downcase }]
    end.select { |_id, models| models.any? }
  end

  def ai_profile_keys
    FeedProfile.ai_profile_keys
  end

  def selected_credential_id
    preferred = [@feed.ai_credential_id, @feed.user.default_ai_credential_id].compact
    selectable_ids = selectable_credentials.map(&:id)
    ((preferred & selectable_ids).first || selectable_ids.first)&.to_s
  end

  def selected_search_credential_id
    preferred = [@feed.search_credential_id, @feed.user.default_search_credential_id].compact
    selectable_ids = active_search_credentials.map(&:id)
    ((preferred & selectable_ids).first || selectable_ids.first)&.to_s
  end

  def credential_options
    selectable_credentials.map do |credential|
      ["#{credential.display_name} · #{credential.llm_provider.display_name}", credential.id]
    end
  end

  def search_credential_options
    active_search_credentials.map do |credential|
      ["#{credential.display_name} · #{credential.provider_label}", credential.id]
    end
  end

  def model_options
    (models_by_credential[selected_credential_id] || []).map { |model| [model["name"], model["id"]] }
  end

  # The blank row is a placeholder, not a choice: disabled (and hidden from the
  # open list) so a feed can't be reverted to "no model" once one is picked. It
  # still shows as the current value while `selected_model_id` is blank.
  def model_select_options
    [["Select a model…", "", { disabled: true, hidden: true }]] + model_options
  end

  def selected_model_id
    model_options.any? { |_name, id| id == @feed.ai_model } ? @feed.ai_model : ""
  end

  def model_unavailable?
    return false unless section_visible?
    return false unless @feed.ai_credential&.active?
    return false if @feed.ai_model.blank?

    !@feed.ai_model_supported?
  end

  private

  attr_reader :feed, :form
end
