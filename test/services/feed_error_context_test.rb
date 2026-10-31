require "test_helper"

class FeedErrorContextTest < ActiveSupport::TestCase
  test ".for should include only feed identity, owner label, and destination" do
    feed = build_stubbed(:feed, access_token: build_stubbed(:access_token))

    assert_equal({
      feed_id: feed.id,
      feed_owner_id: feed.user_id,
      feed_owner_label: feed.user.name,
      freefeed_instance: "candy.freefeed.net",
      target_group: feed.target_group
    }, FeedErrorContext.for(feed))
  end

  test ".for should fall back to the owner's masked email when the name is blank" do
    owner = build_stubbed(:user, name: "", email_address: "alice@example.com")
    feed = build_stubbed(:feed, user: owner)

    assert_equal "a...e@example.com", FeedErrorContext.for(feed)[:feed_owner_label]
  end

  test ".for should omit an unconfigured destination" do
    feed = build_stubbed(:feed, :without_access_token)

    assert_equal({
      feed_id: feed.id,
      feed_owner_id: feed.user_id,
      feed_owner_label: feed.user.name
    }, FeedErrorContext.for(feed))
  end
end
