module LlmProvider
  # Configures OpenAI SDK contexts and Responses requests.
  class Openai < Base
    def protocol
      :responses
    end

    private

    def configure(config)
      config.openai_api_key = credential_data&.fetch("api_key", nil)
      config.default_model = "gpt-6-luna"
    end
  end
end
