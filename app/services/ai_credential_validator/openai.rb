module AiCredentialValidator
  # Checks OpenAI credential fields and authentication.
  class Openai < Base
    def errors
      api_key.is_a?(String) && api_key.present? ? [] : ["Enter your API key"]
    end

    def validate!
      response = HttpClient.build(timeout: 30, follow_redirects: false).get(
        "https://api.openai.com/v1/models",
        headers: { "Authorization" => "Bearer #{api_key}", "Accept" => "application/json" }
      )
      raise_response_error(response) unless response.success?
      true
    rescue HttpClient::Error
      # Omit the original cause so error reports cannot expose credentials.
      raise AiCredentialValidator::Error.new("Couldn't reach OpenAI. Try again later.", category: :connection), cause: nil
    end

    private

    def api_key
      credential_data&.fetch("api_key", nil)
    end

    def rejected_api_key?(status:, code:)
      status == 401 && code == "invalid_api_key"
    end

    def raise_response_error(response)
      data = error_payload(response.body)
      error = data["error"] if data.is_a?(Hash)
      code = error["code"] if error.is_a?(Hash)
      if rejected_api_key?(status: response.status, code: code)
        raise AiCredentialValidator::Error.new("OpenAI rejected this API key. Check or replace it.", category: :invalid_key, status: response.status)
      end

      category = case response.status
      when 401, 403 then :permission
      when 429 then :rate_limit
      else :provider
      end
      raise AiCredentialValidator::Error.new("OpenAI request failed (HTTP #{response.status}). Try again later.", category: category, status: response.status)
    end

    def error_payload(body)
      JSON.parse(body)
    rescue JSON::ParserError, TypeError
      nil
    end
  end
end
