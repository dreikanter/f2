module AiCredentialValidator
  # Checks xAI authentication without a paid inference request.
  class Xai < Base
    def errors
      api_key.is_a?(String) && api_key.present? ? [] : ["Enter your API key"]
    end

    def validate!
      response = HttpClient.build(timeout: 30, follow_redirects: false).get(
        "https://api.x.ai/v1/api-key",
        headers: { "Authorization" => "Bearer #{api_key}", "Accept" => "application/json" }
      )
      raise_response_error(response) unless response.success?

      data = JSON.parse(response.body)
      flags = %w[api_key_blocked api_key_disabled team_blocked]
      unless data.is_a?(Hash) && data["api_key_id"].is_a?(String) && data["api_key_id"].present? &&
             flags.all? { |flag| [true, false].include?(data[flag]) }
        raise AiCredentialValidator::Error.new("xAI returned an invalid key status. Try again later.", category: :provider)
      end
      if flags.any? { |flag| data[flag] }
        raise AiCredentialValidator::Error.new("This xAI key or its team is disabled or blocked. Check your xAI account.", category: :permission)
      end
      true
    rescue JSON::ParserError, TypeError
      raise AiCredentialValidator::Error.new("xAI returned an invalid key status. Try again later.", category: :provider), cause: nil
    rescue HttpClient::Error
      # Omit the original cause so error reports cannot expose credentials.
      raise AiCredentialValidator::Error.new("Couldn't reach xAI. Try again later.", category: :connection), cause: nil
    end

    private

    def api_key
      credential_data&.fetch("api_key", nil)
    end

    def raise_response_error(response)
      if response.status == 401
        raise AiCredentialValidator::Error.new("xAI rejected this API key. Check or replace it.", category: :invalid_key, status: response.status)
      end

      category = case response.status
      when 403 then :permission
      when 429 then :rate_limit
      else :provider
      end
      raise AiCredentialValidator::Error.new("xAI request failed (HTTP #{response.status}). Try again later.", category: category, status: response.status)
    end
  end
end
