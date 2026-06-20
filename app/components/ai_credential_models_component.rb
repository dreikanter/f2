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
  # whatever capabilities the provider reports.
  def model_details(model)
    parts = []
    parts << "#{helpers.number_with_delimiter(model['context_window'])} token context" if model["context_window"].present?
    parts << capabilities(model).join(", ") if capabilities(model).present?
    parts.join(" · ")
  end

  private

  def capabilities(model)
    Array(model["capabilities"]).map { |capability| capability.to_s.tr("_", " ") }
  end
end
