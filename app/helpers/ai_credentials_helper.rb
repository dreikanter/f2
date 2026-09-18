module AiCredentialsHelper
  def default_model_options(credential)
    models = LlmModels.for_feed(credential.provider)
    options = models.map { |model| [model.name.presence || model.id, model.id] }
                    .sort_by { |name, _id| name.downcase }
    if credential.default_model.present? && models.none? { |model| model.id == credential.default_model }
      options << ["#{credential.default_model} (no longer listed)", credential.default_model]
    end
    options
  end
end
