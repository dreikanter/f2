class AiCredentialModelsComponent < ViewComponent::Base
  def initialize(ai_credential:)
    @ai_credential = ai_credential
  end

  def render?
    models.present?
  end

  def models
    @ai_credential.available_models.sort_by { |model| model_name(model).downcase }
  end

  def model_name(model)
    model["name"].presence || model["id"]
  end

  def model_details(model)
    metadata = model.fetch("metadata", {})
    parts = []
    context = metadata["context_window"]
    parts << "#{helpers.number_with_delimiter(context)} token context" if context
    { "tool_call" => "Tools", "structured_output" => "Structured output" }.each do |key, label|
      value = metadata[key]
      parts << "#{label}: #{value.nil? ? 'unknown' : (value ? 'yes' : 'no')}"
    end
    outputs = metadata["output_modalities"]
    parts << "Output: #{outputs.join(', ')}" if outputs.is_a?(Array) && outputs.any?
    parts << "Source: #{metadata['source']}" if metadata["source"]
    parts.join(" · ")
  end
end
