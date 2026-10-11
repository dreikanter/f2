# Adds application-priced native searches to the SDK's frozen token costs.
class LlmUsage < RubyLLM::ActiveRecord::Usage
  self.implicit_order_column = "id"

  # Standard Responses web_search, not the differently priced preview tool.
  # https://developers.openai.com/api/docs/pricing#tools
  SEARCH_REQUEST_COST = BigDecimal("0.01")
  FIXED_SEARCH_CONTENT_MODELS = %w[
    gpt-4o-mini
    gpt-4o-mini-2024-07-18
    gpt-4.1-mini
    gpt-4.1-mini-2025-04-14
  ].freeze

  before_create :record_search_cost

  def estimated_cost
    total_cost + web_search_cost if total_cost && web_search_cost
  end

  private

  def record_search_cost
    self.web_search_cost = 0
    return unless provider == "openai"

    searches = tokens.server_tool_use.to_h.fetch("web_search_requests", 0)
    return unless searches.positive?

    self.web_search_cost = search_request_cost&.*(searches)
  end

  def search_request_cost
    return SEARCH_REQUEST_COST unless FIXED_SEARCH_CONTENT_MODELS.include?(model)

    price = RubyLLM.models.find(model, provider: :openai).price(:input)
    SEARCH_REQUEST_COST + BigDecimal(price.to_s) * 8_000 / 1_000_000 if price
  rescue RubyLLM::ModelNotFoundError => error
    Rails.error.report(error, context: { provider: provider, model: model })
    nil
  end
end
