# The "AI Settings" section of the feed form: the AI provider + model selects,
# or the add-credentials gate when the user has none. All data prep lives here
# so the template stays declarative; the ai-settings Stimulus controller wires
# up visibility and the dependent model list from `models_by_credential`.
class FeedAiSettingsComponent < ViewComponent::Base
  SELECT_CLASSES = "w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-lg leading-normal " \
                   "shadow-xs ring-sky-500 transition focus:border-sky-500 focus:outline-none focus:ring-2".freeze

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

  def credentials?
    active_credentials.any?
  end

  # Each active credential's offered models, keyed by id and embedded so the
  # Stimulus controller can swap the model list on provider change.
  def models_by_credential
    @models_by_credential ||= active_credentials.to_h do |credential|
      models = credential.available_models.map { |model| { "id" => model["id"], "name" => model["name"].presence || model["id"] } }
      [credential.id.to_s, models.sort_by { |model| model["name"].to_s.downcase }]
    end
  end

  def ai_profile_keys
    FeedProfile.all.select { |key| FeedProfile.depends_on_ai?(key) }
  end

  def selected_credential_id
    (@feed.ai_credential_id || @feed.user.default_ai_credential_id || active_credentials.first&.id)&.to_s
  end

  def credential_options
    active_credentials.map do |credential|
      ["#{credential.display_name} · #{LlmProvider.find(credential.provider).display_name}", credential.id]
    end
  end

  def model_options
    (models_by_credential[selected_credential_id] || []).map { |model| [model["name"], model["id"]] }
  end

  # True when the feed's saved model has dropped out of its (still active)
  # credential, so the form should nudge the user to re-pick before re-enabling.
  def model_unavailable?
    return false unless section_visible?
    return false unless @feed.ai_credential&.active?
    return false if @feed.ai_model.blank?

    !@feed.ai_model_available?
  end

  private

  attr_reader :feed, :form
end
