require "test_helper"

class Feed::SearchCredentialTest < ActiveSupport::TestCase
  test "search credential must belong to the feed user" do
    user = create(:user)
    foreign = create(:search_credential, :active)
    feed = build(:feed, user: user, search_credential: foreign)

    assert_not feed.valid?
    assert_includes feed.errors[:search_credential], "must belong to the same user"
  end

  test "enabled AI feeds require an active search credential" do
    feed = build_ai_feed(search_credential: nil)

    assert_not feed.valid?
    assert_includes feed.errors[:search_credential], "must be selected for AI-backed feeds"

    feed.search_credential = create(:search_credential, :inactive, user: feed.user)
    assert_not feed.valid?
    assert_includes feed.errors[:search_credential], "must be active (currently inactive)"
  end

  test "non-AI feeds do not require a search credential" do
    feed = build(:feed, state: :enabled, search_credential: nil)

    feed.valid?
    assert_empty feed.errors[:search_credential]
  end

  test "enablement gating matches the search credential validation" do
    active = create(:search_credential, :active)
    feed = build_ai_feed(user: active.user, search_credential: active)

    assert feed.can_be_enabled?

    feed.search_credential = nil
    assert_not feed.can_be_enabled?
  end

  private

  def build_ai_feed(user: create(:user), search_credential:)
    profile_key = FeedProfile.ai_profile_keys.first
    ai_credential = create(:ai_credential, :active, user: user)
    ai_credential.define_singleton_method(:supports_model?) { |_model| true }

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
