class AiCredentialModelsComponent < ViewComponent::Base
  def initialize(ai_credential:)
    @ai_credential = ai_credential
  end

  def render?
    models.present?
  end

  def models
    @ai_credential.available_models
  end

  def model_name(model)
    model["name"].presence || model["id"]
  end

  # Compact one-liner of the facts worth scanning: context size and
  # whatever capabilities the provider reports. Returns nil when there's
  # nothing to show, so the template can decide with a single call.
  def model_details(model)
    parts = []
    parts << "#{helpers.number_with_delimiter(model['context_window'])} token context" if model["context_window"].present?
    capabilities = capabilities(model)
    parts << capabilities.join(", ") if capabilities.present?
    parts.join(" · ").presence
  end

  private

  def capabilities(model)
    Array(model["capabilities"]).map { |capability| capability.to_s.tr("_", " ") }
  end
end
