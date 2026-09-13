require "test_helper"

class Feed::SearchCredentialTest < ActiveSupport::TestCase
  test "#valid? should require the search credential to belong to the feed user" do
    user = create(:user)
    foreign = create(:search_credential, :active)
    feed = build(:feed, user: user, search_credential: foreign)

    assert_not feed.valid?
    assert_includes feed.errors[:search_credential], "must belong to the same user"
  end

  test "#valid? should allow saved settings with a missing or inactive search credential" do
    feed = build_ai_feed(search_credential: nil)

    assert feed.valid?, feed.errors.full_messages.to_sentence

    feed.search_credential = create(:search_credential, :inactive, user: feed.user)
    assert feed.valid?, feed.errors.full_messages.to_sentence
  end

  test "#valid? should not require a search credential on non-AI feeds" do
    feed = build(:feed, state: :enabled, search_credential: nil)

    feed.valid?
    assert_empty feed.errors[:search_credential]
  end

  private

  def build_ai_feed(user: create(:user), search_credential:)
    profile_key = FeedProfile.ai_profile_keys.first
    ai_credential = create(:ai_credential, :active, user: user, available_models: [{ "id" => "test-model" }])

    build(
      :feed,
      user: user,
      state: :enabled,
      feed_profile_key: profile_key,
      params: { FeedProfile.source_key_for(profile_key) => "Ruby news" },
      ai_credential: ai_credential,
      search_credential: search_credential,
      ai_model: "test-model"
    )
  end
end
