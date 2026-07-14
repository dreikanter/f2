require "test_helper"

class SearchCredential::FeedLifecycleTest < ActiveSupport::TestCase
  test "deactivation disables enabled dependent feeds" do
    credential = create(:search_credential, :active)
    enabled = create(:feed, :enabled, user: credential.user, search_credential: credential)
    disabled = create(:feed, :disabled, user: credential.user, search_credential: credential)

    credential.deactivate!(last_error: "Invalid key")

    assert enabled.reload.disabled?
    assert disabled.reload.disabled?
    assert_equal credential.id, enabled.search_credential_id
  end

  test "destroy nullifies the reference and disables enabled dependent feeds" do
    credential = create(:search_credential, :active)
    enabled = create(:feed, :enabled, user: credential.user, search_credential: credential)
    disabled = create(:feed, :disabled, user: credential.user, search_credential: credential)

    credential.destroy!

    assert enabled.reload.disabled?
    assert_nil enabled.search_credential_id
    assert disabled.reload.disabled?
    assert_nil disabled.search_credential_id
  end
end
