require "test_helper"

class SearchCredential::FeedLifecycleTest < ActiveSupport::TestCase
  test "#deactivate! should preserve dependent feed states" do
    credential = create(:search_credential, :active)
    enabled = create(:feed, :enabled, user: credential.user, search_credential: credential)
    disabled = create(:feed, :disabled, user: credential.user, search_credential: credential)

    credential.deactivate!(last_error: "Invalid key")

    assert enabled.reload.enabled?
    assert disabled.reload.disabled?
    assert_equal credential.id, enabled.search_credential_id
  end

  test "#destroy! should nullify the reference and preserve dependent feed states" do
    credential = create(:search_credential, :active)
    enabled = create(:feed, :enabled, user: credential.user, search_credential: credential)
    disabled = create(:feed, :disabled, user: credential.user, search_credential: credential)

    credential.destroy!

    assert enabled.reload.enabled?
    assert_nil enabled.search_credential_id
    assert disabled.reload.disabled?
    assert_nil disabled.search_credential_id
  end
end
