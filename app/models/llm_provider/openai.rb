module LlmProvider
  class Openai < Base
    def initialize
      super(name: "openai", display_name: "OpenAI", default_model: "gpt-5.6-luna")
    end

    def models(api_key:)
      response = HttpClient.build(timeout: 30, follow_redirects: false).get(
        "https://api.openai.com/v1/models",
        headers: { "Authorization" => "Bearer #{api_key}", "Accept" => "application/json" }
      )
      raise_response_error(response) unless response.success?
      data = parse_json(response.body)
      unless data.is_a?(Hash) && data["data"].is_a?(Array) && data["data"].all? { |model| valid_model?(model) }
        raise AiModelCatalog::Error.new("OpenAI returned an invalid model list.", category: :malformed)
      end

      data["data"].pluck("id").uniq
    rescue HttpClient::Error
      raise AiModelCatalog::Error.new("Couldn't reach OpenAI. Try again later.", category: :connection), cause: nil
    end

    private

    def configure(config, api_key)
      config.openai_api_key = api_key
    end

    def rejected_api_key?(status:, code:)
      status == 401 && code == "invalid_api_key"
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError, TypeError
      raise AiModelCatalog::Error.new("OpenAI returned an invalid model list.", category: :malformed), cause: nil
    end

    def valid_model?(model)
      model.is_a?(Hash) && model["id"].is_a?(String) && model["id"].present? && model["id"] == model["id"].strip
    end

    def raise_response_error(response)
      data = error_payload(response.body)
      error = data["error"] if data.is_a?(Hash)
      code = error["code"] if error.is_a?(Hash)
      if rejected_api_key?(status: response.status, code: code)
        raise AiModelCatalog::Error.new("OpenAI rejected this API key. Check or replace it.", category: :invalid_key, status: response.status)
      end

      category = case response.status
      when 401, 403 then :permission
      when 429 then :rate_limit
      else :provider
      end
      raise AiModelCatalog::Error.new("Couldn't list OpenAI models (HTTP #{response.status}). Try again later.", category: category, status: response.status)
    end

    def error_payload(body)
      JSON.parse(body)
    rescue JSON::ParserError, TypeError
      nil
    end
  end
end
