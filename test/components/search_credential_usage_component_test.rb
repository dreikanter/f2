require "test_helper"
require "view_component/test_case"

class SearchCredentialUsageComponentTest < ViewComponent::TestCase
  def credential
    @credential ||= create(:search_credential, :active)
  end

  def record_calls(count, at:)
    count.times do
      create(:event, type: "web_search", level: :debug, subject: credential, user: credential.user,
                     metadata: { "provider" => credential.provider, "outcome" => "success" }, created_at: at)
    end
  end

  test "#render should show window-scoped call counts with estimated cost" do
    record_calls(12, at: 1.hour.ago)
    record_calls(8, at: 3.days.ago)
    record_calls(10, at: 20.days.ago)
    record_calls(5, at: 40.days.ago)

    result = render_inline(SearchCredentialUsageComponent.new(search_credential: credential))

    assert_equal "12 searches · ~$0.01", result.css('[data-key="search_credential.usage.day.value"]').first.text.strip
    assert_equal "20 searches · ~$0.02", result.css('[data-key="search_credential.usage.week.value"]').first.text.strip
    assert_equal "30 searches · ~$0.03", result.css('[data-key="search_credential.usage.month.value"]').first.text.strip
  end

  test "#render should show zeros for an unused credential" do
    result = render_inline(SearchCredentialUsageComponent.new(search_credential: credential))

    assert_equal "0 searches · ~$0.00", result.css('[data-key="search_credential.usage.day.value"]').first.text.strip
  end

  test "#render should not count another credential's calls" do
    other = create(:search_credential, :active, user: credential.user, display_name: "Other")
    create(:event, type: "web_search", level: :debug, subject: other, user: credential.user,
                   metadata: { "provider" => other.provider }, created_at: 1.hour.ago)

    result = render_inline(SearchCredentialUsageComponent.new(search_credential: credential))

    assert_equal "0 searches · ~$0.00", result.css('[data-key="search_credential.usage.day.value"]').first.text.strip
  end
end
