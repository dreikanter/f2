require "test_helper"

class FeedPreviewTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def feed_profile
    @feed_profile ||= create(:feed_profile, user: user)
  end

  def feed_preview
    @feed_preview ||= create(:feed_preview, user: user, feed_profile: feed_profile)
  end

  test "should belong to user" do
    assert_equal user, feed_preview.user
  end

  test "should belong to feed_profile" do
    assert_equal feed_profile, feed_preview.feed_profile
  end

  test "should validate presence of url" do
    preview = build(:feed_preview, url: nil, user: user, feed_profile: feed_profile)
    assert_not preview.valid?
    assert_includes preview.errors[:url], "can't be blank"
  end

  test "should validate presence of feed_profile" do
    preview = build(:feed_preview, feed_profile: nil, user: user)
    assert_not preview.valid?
    assert_includes preview.errors[:feed_profile], "can't be blank"
  end

  test "should validate url format" do
    preview = build(:feed_preview, url: "invalid-url", user: user, feed_profile: feed_profile)
    assert_not preview.valid?
    assert_includes preview.errors[:url], "must be a valid HTTP or HTTPS URL"
  end

  test "should allow valid http url" do
    preview = build(:feed_preview, url: "http://example.com/feed.xml", user: user, feed_profile: feed_profile)
    assert preview.valid?
  end

  test "should allow valid https url" do
    preview = build(:feed_preview, url: "https://example.com/feed.xml", user: user, feed_profile: feed_profile)
    assert preview.valid?
  end

  test "should validate uniqueness of url scoped to feed_profile" do
    existing = create(:feed_preview, url: "http://example.com/feed.xml", user: user, feed_profile: feed_profile)
    duplicate = build(:feed_preview, url: "http://example.com/feed.xml", user: user, feed_profile: feed_profile)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:url], "has already been taken"
  end

  test "should allow same url with different feed_profile" do
    profile2 = create(:feed_profile, user: user, name: "profile2")
    existing = create(:feed_preview, url: "http://example.com/feed.xml", user: user, feed_profile: feed_profile)
    different_profile = build(:feed_preview, url: "http://example.com/feed.xml", user: user, feed_profile: profile2)

    assert different_profile.valid?
  end

  test "should normalize url by stripping whitespace" do
    preview = create(:feed_preview, url: "  http://example.com/feed.xml  ", user: user, feed_profile: feed_profile)
    assert_equal "http://example.com/feed.xml", preview.url
  end

  test "should have status enum" do
    preview = create(:feed_preview, user: user, feed_profile: feed_profile)

    assert preview.pending?

    preview.processing!
    assert preview.processing?

    preview.ready!
    assert preview.ready?

    preview.failed!
    assert preview.failed?
  end

  test "posts_data should return empty array when data is nil" do
    preview = create(:feed_preview, user: user, feed_profile: feed_profile, data: nil)
    assert_equal [], preview.posts_data
  end

  test "posts_data should return empty array when not ready" do
    preview = create(:feed_preview, user: user, feed_profile: feed_profile, status: :pending, data: { "posts" => [{ "title" => "Test" }] })
    assert_equal [], preview.posts_data
  end

  test "posts_data should return posts when ready and data present" do
    posts = [{ "title" => "Test Post" }]
    preview = create(:feed_preview, user: user, feed_profile: feed_profile, status: :ready, data: { "posts" => posts })
    assert_equal posts, preview.posts_data
  end

  test "posts_count should return size of posts_data" do
    posts = [{ "title" => "Test Post 1" }, { "title" => "Test Post 2" }]
    preview = create(:feed_preview, user: user, feed_profile: feed_profile, status: :ready, data: { "posts" => posts })
    assert_equal 2, preview.posts_count
  end

  test "posts_count should return 0 when no posts" do
    preview = create(:feed_preview, user: user, feed_profile: feed_profile, data: nil)
    assert_equal 0, preview.posts_count
  end

  test "should have recent scope" do
    old_preview = create(:feed_preview, user: user, feed_profile: feed_profile, created_at: 2.days.ago)
    new_preview = create(:feed_preview, user: user, feed_profile: create(:feed_profile, user: user, name: "profile2"), created_at: 1.day.ago)

    recent = FeedPreview.recent
    assert_equal [new_preview, old_preview], recent.to_a
  end

  test "should have for_cache_key scope" do
    url = "http://example.com/feed.xml"
    profile2 = create(:feed_profile, user: user, name: "profile2")
    matching = create(:feed_preview, url: url, feed_profile: feed_profile, user: user)
    non_matching = create(:feed_preview, url: "http://other.com/feed.xml", feed_profile: profile2, user: user)

    result = FeedPreview.for_cache_key(url, feed_profile.id)
    assert_includes result, matching
    assert_not_includes result, non_matching
  end
end