class AiModelCatalog
  UNAVAILABLE_MESSAGE = "AI model discovery is temporarily unavailable. Your saved settings are still available.".freeze

  class Error < StandardError
    attr_reader :category, :status

    def initialize(message, category:, status: nil)
      @category = category
      @status = status
      super(message)
    end

    def invalid_key?
      category == :invalid_key
    end
  end

  class Unavailable < Error
    def initialize
      super(UNAVAILABLE_MESSAGE, category: :unavailable)
    end
  end

  def self.fetch(credential)
    new(credential).fetch
  end

  def initialize(credential)
    @provider = credential.llm_provider
    @api_key = credential.credential_data.fetch("api_key")
  end

  def fetch
    implementation = @provider.implementation
    raise Unavailable unless implementation

    ids = implementation.models(api_key: @api_key)
    metadata = RubyLLM.models.by_provider(@provider.name).index_by(&:id)
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
        "structured_output" => model.supports?(:structured_output),
        "task" => model.metadata["task"]
      }.compact
    }
  end
end
