# A user's API credential for one web search provider. Lifecycle, naming, and
# feed teardown come from ProviderCredential; what's here is the cost side,
# since search is billed per request and gets estimated before a run.
class SearchCredential < ApplicationRecord
  include ProviderCredential

  REMOVED_EVENT_TYPE = "feed_search_credential_removed"
  DEACTIVATED_EVENT_TYPE = "search_credential_deactivated"

  validates :provider, presence: true, inclusion: { in: ->(_) { WebSearchProvider::REGISTRY.keys } }

  def web_search_provider
    WebSearchProvider.for(provider, api_key: credential_data["api_key"])
  end

  def provider_label
    WebSearchProvider.label_for(provider)
  end

  alias_method :provider_name, :provider_label

  def estimated_search_cost_cents(call_count)
    BigDecimal(WebSearchProvider.cents_per_1k_requests_for(provider).to_s) * call_count / 1000
  end
end
