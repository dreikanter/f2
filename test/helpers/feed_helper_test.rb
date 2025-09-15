require "test_helper"

class FeedHelperTest < ActionView::TestCase
  test "feed_missing_enablement_parts returns both missing parts" do
    feed = create(:feed, :without_access_token)

    result = feed_missing_enablement_parts(feed)

    assert_equal ["active access token", "target group"], result
  end

  test "feed_missing_enablement_parts returns missing access token only" do
    feed = create(:feed, :without_access_token, target_group: "test_group")

    result = feed_missing_enablement_parts(feed)

    assert_equal ["active access token"], result
  end

  test "feed_missing_enablement_parts returns missing target group only" do
    access_token = create(:access_token, :active)
    feed = create(:feed, access_token: access_token, target_group: nil)

    result = feed_missing_enablement_parts(feed)

    assert_equal ["target group"], result
  end

  test "feed_missing_enablement_parts returns missing access token when inactive" do
    access_token = create(:access_token, :inactive)
    feed = create(:feed, access_token: access_token, target_group: "test_group")

    result = feed_missing_enablement_parts(feed)

    assert_equal ["active access token"], result
  end

  test "feed_missing_enablement_parts returns empty array when all requirements met" do
    access_token = create(:access_token, :active)
    feed = create(:feed, access_token: access_token, target_group: "test_group")

    result = feed_missing_enablement_parts(feed)

    assert_equal [], result
  end
end
