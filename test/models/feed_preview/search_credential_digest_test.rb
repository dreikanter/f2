require "test_helper"

class FeedPreview::SearchCredentialDigestTest < ActiveSupport::TestCase
  test "changing the search credential changes the preview digest" do
    profile_key = FeedProfile.ai_profile_keys.first
    params = { FeedProfile.source_key_for(profile_key) => "Ruby news" }
    ai_credential_id = SecureRandom.uuid
    first_search_credential_id = SecureRandom.uuid
    second_search_credential_id = SecureRandom.uuid

    first = FeedPreview.digest_for(profile_key, params, ai_credential_id, "model", first_search_credential_id)
    second = FeedPreview.digest_for(profile_key, params, ai_credential_id, "model", second_search_credential_id)

    assert_not_equal first, second
  end
end
