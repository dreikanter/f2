# The "AI Settings" section of the feed form: the AI provider + model selects,
# or the add-credentials gate when the user has none. All data prep lives here
# so the template stays declarative; the ai-settings Stimulus controller wires
# up visibility and the dependent model list from `models_by_credential`.
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

  # Active credentials that can actually back a feed: those offering at least one
  # capability-matrix model. A credential whose provider we haven't verified (no
  # matrix rows) or whose live snapshot no longer overlaps the matrix would leave
  # the model picker empty, so we don't offer it as a choice at all.
  def selectable_credentials
    @selectable_credentials ||= active_credentials.select { |credential| models_by_credential.key?(credential.id.to_s) }
  end

  def credentials?
    selectable_credentials.any?
  end

  # Each selectable credential's models, keyed by id and embedded so the Stimulus
  # controller can swap the model list on provider change. Gated to the capability
  # matrix ∩ the credential's live snapshot, so only dev-verified web+schema models
  # are offered (spec §5); credentials left with no models are dropped entirely.
  def models_by_credential
    @models_by_credential ||= active_credentials.to_h do |credential|
      models = credential.supported_models
                         .map { |model| { "id" => model["id"], "name" => model["name"].presence || model["id"] } }
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

  def credential_options
    selectable_credentials.map do |credential|
      ["#{credential.display_name} · #{credential.llm_provider.display_name}", credential.id]
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

  # True when the feed's saved model can no longer be picked — it dropped out of
  # the matrix ∩ the credential's live snapshot — so the form should nudge the
  # user to re-pick before re-enabling.
  def model_unavailable?
    return false unless section_visible?
    return false unless @feed.ai_credential&.active?
    return false if @feed.ai_model.blank?

    !@feed.ai_model_supported?
  end

  private

  attr_reader :feed, :form
end
