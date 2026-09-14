class AiCredentialModelsComponent < ViewComponent::Base
  def initialize(ai_credential:)
    @provider = ai_credential.provider
  end

  def render?
    models.present?
  end

  def models
    @models ||= LlmModels.for_provider(@provider).sort_by { |model| model_name(model).downcase }
  end

  def model_name(model)
    model.name.presence || model.id
  end

  def model_details(model)
    parts = []
    parts << "#{helpers.number_with_delimiter(model.context_window)} token context" if model.context_window
    { "Tools" => :function_calling, "Structured output" => :structured_output }.each do |label, capability|
      value = model.capabilities.empty? ? "unknown" : (model.supports?(capability) ? "yes" : "no")
      parts << "#{label}: #{value}"
    end
    parts << "Output: #{model.modalities.output.join(', ')}" if model.modalities.output.any?
    parts << "Source: RubyLLM"
    parts.join(" · ")
  end
end
