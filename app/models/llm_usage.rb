# Adds application-priced native searches to the SDK's frozen token costs.
class LlmUsage < RubyLLM::ActiveRecord::Usage
  self.implicit_order_column = "id"

  before_create :record_search_cost

  def estimated_cost
    total_cost + web_search_cost if total_cost && web_search_cost
  end

  private

  def record_search_cost
    self.web_search_cost = 0
    return unless LlmProvider.names.include?(provider)

    adapter = LlmProvider.build(provider, credential_data: {})
    searches = tokens.server_tool_use.to_h.fetch("web_search_requests", 0)
    self.web_search_cost = adapter.search_cost(model: model, searches: searches)
  end
end
