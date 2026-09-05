class AiModelCatalog
  def self.fetch(credential, allow_empty: false)
    models = LlmClient.for(credential).available_models
    raise LlmClient::ProviderError, "Models listing was empty" if models.empty? && !allow_empty

    metadata = PublishedModelMetadata.new
    previous = credential.available_models.index_by { |model| model["id"] }

    models.map do |model|
      details = metadata.lookup(credential.provider, model.fetch("id")) || previous.dig(model["id"], "metadata")
      model.slice("id", "name").merge("metadata" => details).compact
    end
  end
end
