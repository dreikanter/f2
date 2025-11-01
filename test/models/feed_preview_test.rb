require "test_helper"

class FeedPreviewTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def feed_preview
    @feed_preview ||= create(:feed_preview, user: user)
  end

  test "should belong to user" do
    assert_equal user, feed_preview.user
  end

  test "should have feed_profile_key" do
    assert_equal "rss", feed_preview.feed_profile_key
  end

  test "should validate presence of url" do
    preview = build(:feed_preview, url: nil, user: user)
    assert_not preview.valid?
    assert preview.errors.of_kind?(:url, :blank)
  end

  test "should validate presence of feed_profile_key" do
    preview = build(:feed_preview, feed_profile_key: nil, user: user)
    assert_not preview.valid?
    assert preview.errors.of_kind?(:feed_profile_key, :blank)
  end

  test "should validate url format" do
    preview = build(:feed_preview, url: "invalid-url", user: user)
    assert_not preview.valid?
    assert_includes preview.errors[:url], "must be a valid HTTP or HTTPS URL"
  end

  test "should allow valid http url" do
    preview = build(
      :feed_preview,
      url: "http://example.com/feed.xml",
      user: user
    )

    assert preview.valid?
  end

  test "should allow valid https url" do
    preview = build(
      :feed_preview,
      url: "https://example.com/feed.xml",
      user: user
    )

    assert preview.valid?
  end

  test "should validate uniqueness of url scoped to feed_profile_key" do
    existing = create(:feed_preview,
      url: "http://example.com/feed.xml",
      user: user
    )

    duplicate = build(:feed_preview,
      url: "http://example.com/feed.xml",
      user: user
    )

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:url, :taken)
  end

  test "should allow same url with different feed_profile_key" do
    existing = create(
      :feed_preview,
      url: "http://example.com/feed.xml",
      feed_profile_key: "rss",
      user: user
    )

    different_profile = build(:feed_preview,
      url: "http://example.com/feed.xml",
      feed_profile_key: "xkcd",
      user: user
    )

    assert different_profile.valid?
  end

  test "should normalize url by stripping whitespace" do
    preview = create(
      :feed_preview,
      url: "  http://example.com/feed.xml  ",
      user: user
    )

    assert_equal "http://example.com/feed.xml", preview.url
  end

  test "should have status enum" do
    preview = create(:feed_preview, user: user)

    assert preview.pending?

    preview.processing!
    assert preview.processing?

    preview.ready!
    assert preview.ready?

    preview.failed!
    assert preview.failed?
  end

  test "#posts_data should return empty array when data is nil" do
    preview = create(:feed_preview, user: user, data: nil)
    assert_equal [], preview.posts_data
  end

  test "#posts_data should return empty array when not ready" do
    preview = create(
      :feed_preview,
      user: user,
      status: :pending,
      data: { "posts" => [{ "title" => "Test" }] }
    )

    assert_equal [], preview.posts_data
  end

  test "#posts_data should return posts when ready and data present" do
    posts = [{ "title" => "Test Post" }]

    preview = create(
      :feed_preview,
      user: user,
      status: :ready,
      data: { "posts" => posts }
    )

    assert_equal posts, preview.posts_data
  end

  test "#posts_count should return size of posts_data" do
    posts = [{ "title" => "Test Post 1" }, { "title" => "Test Post 2" }]

    preview = create(
      :feed_preview,
      user: user,
      status: :ready,
      data: { "posts" => posts }
    )

    assert_equal 2, preview.posts_count
  end

  test "#posts_count should return 0 when no posts" do
    preview = create(:feed_preview, user: user, data: nil)
    assert_equal 0, preview.posts_count
  end

  test "should have for_cache_key scope" do
    url = "http://example.com/feed.xml"
    matching = create(:feed_preview, url: url, feed_profile_key: "rss", user: user)

    non_matching = create(
      :feed_preview,
      url: "http://other.com/feed.xml",
      feed_profile_key: "xkcd",
      user: user
    )

    result = FeedPreview.for_cache_key(url, "rss")
    assert_includes result, matching
    assert_not_includes result, non_matching
  end
end
