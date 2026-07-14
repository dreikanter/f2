require "test_helper"
require "view_component/test_case"

class SearchCredentialUsageStatsComponentTest < ViewComponent::TestCase
  test "#render should show bounded counts and fractional estimated spend" do
    credential = create(:search_credential, :active, provider: "serper")
    now = Time.zone.parse("2026-07-14 12:00:00")
    travel_to(now) { WebSearchUsage.record!(credential: credential) }
    travel_to(now - 2.days) { WebSearchUsage.record!(credential: credential) }
    travel_to(now - 8.days) { WebSearchUsage.record!(credential: credential) }
    travel_to(now - 31.days) { WebSearchUsage.record!(credential: credential) }

    travel_to(now) do
      result = render_inline(SearchCredentialUsageStatsComponent.new(search_credential: credential))

      assert_equal "1", result.css('[data-key="search_credential.usage.day.calls.value"]').first.text.strip
      assert_equal "$0.00100", result.css('[data-key="search_credential.usage.day.cost.value"]').first.text.strip
      assert_equal "2", result.css('[data-key="search_credential.usage.week.calls.value"]').first.text.strip
      assert_equal "$0.00200", result.css('[data-key="search_credential.usage.week.cost.value"]').first.text.strip
      assert_equal "3", result.css('[data-key="search_credential.usage.month.calls.value"]').first.text.strip
      assert_equal "$0.00300", result.css('[data-key="search_credential.usage.month.cost.value"]').first.text.strip
    end
  end
end
