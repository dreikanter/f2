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
    raise Unavailable unless @provider.discovery_available?

    response = HttpClient.build(timeout: 30, follow_redirects: false).get(
      "https://api.openai.com/v1/models",
      headers: { "Authorization" => "Bearer #{@api_key}", "Accept" => "application/json" }
    )
    raise_response_error(response) unless response.success?
    data = parse_json(response.body)
    unless data.is_a?(Hash) && data["data"].is_a?(Array) && data["data"].all? { |model| valid_model?(model) }
      raise Error.new("OpenAI returned an invalid model list.", category: :malformed)
    end

    metadata = RubyLLM.models.by_provider(:openai).index_by(&:id)
    data["data"].map { |model| catalog_entry(model.fetch("id"), metadata[model.fetch("id")]) }.uniq { |model| model["id"] }
  rescue HttpClient::Error
    raise Error.new("Couldn't reach OpenAI. Try again later.", category: :connection), cause: nil
  end

  private

  def parse_json(body)
    JSON.parse(body)
  rescue JSON::ParserError, TypeError
    raise Error.new("OpenAI returned an invalid model list.", category: :malformed), cause: nil
  end

  def valid_model?(model)
    model.is_a?(Hash) && model["id"].is_a?(String) && model["id"].present? && model["id"] == model["id"].strip
  end

  def raise_response_error(response)
    data = error_payload(response.body)
    error = data["error"] if data.is_a?(Hash)
    code = error["code"] if error.is_a?(Hash)
    if @provider.rejected_api_key?(status: response.status, code: code)
      raise Error.new("OpenAI rejected this API key. Check or replace it.", category: :invalid_key, status: response.status)
    end

    category = case response.status
    when 401, 403 then :permission
    when 429 then :rate_limit
    else :provider
    end
    raise Error.new("Couldn't list OpenAI models (HTTP #{response.status}). Try again later.", category: category, status: response.status)
  end

  def error_payload(body)
    JSON.parse(body)
  rescue JSON::ParserError, TypeError
    nil
  end

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
