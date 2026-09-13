# Fetches model IDs through a credential's provider client and enriches them
# with advisory SDK metadata for validation and catalog-refresh operations.
class AiModelCatalog
  UNAVAILABLE_MESSAGE = "AI model discovery is temporarily unavailable. Your saved settings are still available.".freeze

  def self.fetch(credential)
    new(credential).fetch
  end

  def initialize(credential)
    @provider_name = credential.provider
    @client = credential.build_llm_client
  end

  def fetch
    ids = @client.models
    metadata = RubyLLM.models.by_provider(@provider_name).index_by(&:id)
    ids.map { |id| catalog_entry(id, metadata[id]) }
  end

  private

  def catalog_entry(id, model)
    return { "id" => id, "name" => id } unless model

    {
      "id" => id,
      "name" => model.name.presence || id,
      "metadata" => {
        "source" => "RubyLLM",
        "context_window" => model.context_window,
        "max_output_tokens" => model.max_output_tokens,
        "output_modalities" => model.modalities.output.presence,
        "tool_call" => model.supports?(:function_calling),
        "structured_output" => model.supports?(:structured_output)
      }.compact
    }
  end
end
