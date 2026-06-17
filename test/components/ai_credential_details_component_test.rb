require "test_helper"
require "view_component/test_case"

class AiCredentialDetailsComponentTest < ViewComponent::TestCase
  test "#render should show provider display name" do
    credential = create(:ai_credential, provider: "openrouter")

    result = render_inline(AiCredentialDetailsComponent.new(ai_credential: credential))

    assert_includes result.css('[data-key="ai_credential.provider.value"]').first.text, "OpenRouter"
  end

  test "#render should show created date" do
    credential = create(:ai_credential)

    result = render_inline(AiCredentialDetailsComponent.new(ai_credential: credential))

    assert_not_nil result.css('[data-key="ai_credential.created.value"]').first
  end

  test "#render should show last used when last_validated_at is present" do
    credential = create(:ai_credential, :active)

    result = render_inline(AiCredentialDetailsComponent.new(ai_credential: credential))

    assert_not_nil result.css('[data-key="ai_credential.last_used.value"]').first
  end

  test "#render should not show last used when last_validated_at is absent" do
    credential = create(:ai_credential, state: :pending)

    result = render_inline(AiCredentialDetailsComponent.new(ai_credential: credential))

    assert_nil result.css('[data-key="ai_credential.last_used.value"]').first
  end
end
