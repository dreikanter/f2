require "test_helper"

class WebSearchProviderRatesTest < ActiveSupport::TestCase
  test ".cents_per_1k_requests_for should return the configured rates" do
    assert_equal 100, WebSearchProvider.cents_per_1k_requests_for("serper")
    assert_equal 500, WebSearchProvider.cents_per_1k_requests_for("brave")
    assert_equal 800, WebSearchProvider.cents_per_1k_requests_for("tavily")
  end

  test ".options_for_select should preserve labels and registry order" do
    assert_equal [
      ["Serper", "serper"],
      ["Brave", "brave"],
      ["Tavily", "tavily"]
    ], WebSearchProvider.options_for_select
  end
end
