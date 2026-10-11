module LlmProvider
  # OpenAI request configuration and supplemental search pricing.
  class Openai < Base
    # Standard Responses web_search, not the differently priced preview tool.
    # https://developers.openai.com/api/docs/pricing#tools
    SEARCH_REQUEST_COST = BigDecimal("0.01")

    # Converts input price per million tokens to fixed content cost per search.
    SEARCH_CONTENT_COST_MULTIPLIER = BigDecimal("0.008")

    FIXED_SEARCH_CONTENT_MODELS = %w[
      gpt-4o-mini
      gpt-4o-mini-2024-07-18
      gpt-4.1-mini
      gpt-4.1-mini-2025-04-14
    ].freeze

    def protocol
      :responses
    end

    def search_cost(model:, searches:)
      return 0 unless searches.positive?

      search_request_cost(model)&.*(searches)
    end

    private

    def search_request_cost(model)
      return SEARCH_REQUEST_COST unless FIXED_SEARCH_CONTENT_MODELS.include?(model)

      price = RubyLLM.models.find(model, provider: :openai).price(:input)
      SEARCH_REQUEST_COST + BigDecimal(price.to_s) * SEARCH_CONTENT_COST_MULTIPLIER if price
    rescue RubyLLM::ModelNotFoundError => error
      Rails.error.report(error, context: { provider: "openai", model: model })
      nil
    end

    def configure(config)
      config.openai_api_key = credential_data&.fetch("api_key", nil)
    end
  end
end
