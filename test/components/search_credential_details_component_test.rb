require "test_helper"
require "view_component/test_case"

class SearchCredentialDetailsComponentTest < ViewComponent::TestCase
  test "#render should show provider display name" do
    credential = create(:search_credential, provider: "brave")

    result = render_inline(SearchCredentialDetailsComponent.new(search_credential: credential))

    assert_includes result.css('[data-key="search_credential.provider.value"]').first.text, "Brave"
  end

  test "#render should show created date" do
    credential = create(:search_credential)

    result = render_inline(SearchCredentialDetailsComponent.new(search_credential: credential))

    assert_not_nil result.css('[data-key="search_credential.created.value"]').first
  end

  test "#render should show last checked when last_validated_at is present" do
    credential = create(:search_credential, :active)

    result = render_inline(SearchCredentialDetailsComponent.new(search_credential: credential))

    assert_not_nil result.css('[data-key="search_credential.last_checked.value"]').first
  end

  test "#render should not show last checked when last_validated_at is absent" do
    credential = create(:search_credential, state: :pending)

    result = render_inline(SearchCredentialDetailsComponent.new(search_credential: credential))

    assert_nil result.css('[data-key="search_credential.last_checked.value"]').first
  end
end
