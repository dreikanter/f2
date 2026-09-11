require "test_helper"

class SearchCredentialUsageTest < ActiveSupport::TestCase
  test "#provider_name should come from the provider registry" do
    credential = build(:search_credential, provider: "brave")

    assert_equal "Brave", credential.provider_name
  end

  test "#estimated_search_cost_cents should preserve fractional cents" do
    credential = build(:search_credential, provider: "tavily")

    assert_equal BigDecimal("2.4"), credential.estimated_search_cost_cents(3)
  end
end
