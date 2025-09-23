require "test_helper"

class FeedPreviewTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def feed_profile
    @feed_profile ||= create(:feed_profile, user: user)
  end

  def feed
    @feed ||= create(:feed, user: user, feed_profile: feed_profile)
  end

  test "should be valid with all required attributes" do
    preview = build(:feed_preview, feed_profile: feed_profile)
    assert preview.valid?
  end

  test "should require url" do
    preview = build(:feed_preview, url: nil, feed_profile: feed_profile)
    assert_not preview.valid?
    assert preview.errors.of_kind?(:url, :blank)
  end

  test "should require feed_profile" do
    preview = build(:feed_preview, feed_profile: nil)
    assert_not preview.valid?
    assert preview.errors.of_kind?(:feed_profile, :blank)
  end

  test "should validate url format" do
    preview = build(:feed_preview, url: "not-a-url", feed_profile: feed_profile)
    assert_not preview.valid?
    assert preview.errors.of_kind?(:url, :invalid)

    preview = build(:feed_preview, url: "ftp://example.com", feed_profile: feed_profile)
    assert_not preview.valid?
    assert preview.errors.of_kind?(:url, :invalid)

    preview = build(:feed_preview, url: "https://example.com/feed.xml", feed_profile: feed_profile)
    assert preview.valid?
  end

  test "should enforce unique url per feed_profile" do
    create(:feed_preview, url: "https://example.com/feed.xml", feed_profile: feed_profile)

    duplicate_preview = build(:feed_preview, url: "https://example.com/feed.xml", feed_profile: feed_profile)
    assert_not duplicate_preview.valid?
    assert duplicate_preview.errors.of_kind?(:url, :taken)
  end

  test "should allow same url for different feed_profiles" do
    other_profile = create(:feed_profile, user: user, name: "other-profile")
    create(:feed_preview, url: "https://example.com/feed.xml", feed_profile: feed_profile)

    preview2 = build(:feed_preview, url: "https://example.com/feed.xml", feed_profile: other_profile)
    assert preview2.valid?
  end

  test "should have pending status by default" do
    preview = build(:feed_preview, feed_profile: feed_profile)
    assert_equal "pending", preview.status
  end

  test "should support status transitions" do
    preview = create(:feed_preview, feed_profile: feed_profile)

    assert preview.pending?

    preview.processing!
    assert preview.processing?

    preview.completed!
    assert preview.completed?
    assert preview.ready?

    preview.failed!
    assert preview.failed?
  end

  test "should normalize url by stripping spaces" do
    preview = create(:feed_preview, url: "  https://example.com/feed.xml  ", feed_profile: feed_profile)
    assert_equal "https://example.com/feed.xml", preview.url
  end

  test "processing? should return true only for processing status" do
    preview = create(:feed_preview, feed_profile: feed_profile, status: :pending)
    assert_not preview.processing?

    preview.update!(status: :processing)
    assert preview.processing?

    preview.update!(status: :completed)
    assert_not preview.processing?

    preview.update!(status: :failed)
    assert_not preview.processing?
  end

  test "posts_data should return empty array when data is nil" do
    preview = create(:feed_preview, feed_profile: feed_profile, data: nil)
    assert_equal [], preview.posts_data
  end

  test "posts_data should return empty array when status is not completed" do
    preview = create(:feed_preview, feed_profile: feed_profile, status: :pending, data: { posts: [{ content: "test" }] })
    assert_equal [], preview.posts_data
  end

  test "posts_data should return posts when completed" do
    posts_data = [{ "content" => "Test post", "source_url" => "https://example.com" }]
    preview = create(:feed_preview, feed_profile: feed_profile, status: :completed, data: { posts: posts_data })
    assert_equal posts_data, preview.posts_data
  end

  test "posts_count should return correct count" do
    posts_data = [{ "content" => "Post 1" }, { "content" => "Post 2" }]
    preview = create(:feed_preview, feed_profile: feed_profile, status: :completed, data: { posts: posts_data })
    assert_equal 2, preview.posts_count
  end


  test "find_or_create_for_preview should return existing recent preview" do
    existing = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml")

    result = FeedPreview.find_or_create_for_preview(
      url: "https://example.com/feed.xml",
      feed_profile: feed_profile
    )

    assert_equal existing, result
  end

  test "find_or_create_for_preview should create new preview when existing is old" do
    existing = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml")
    existing.update_column(:created_at, 2.hours.ago)

    assert_difference("FeedPreview.count", 0) do # existing will be destroyed, new one created
      result = FeedPreview.find_or_create_for_preview(
        url: "https://example.com/feed.xml",
        feed_profile: feed_profile
      )
      assert_not_equal existing.id, result.id
    end
  end

  test "find_or_create_for_preview should create new preview when none exists" do
    assert_difference("FeedPreview.count", 1) do
      result = FeedPreview.find_or_create_for_preview(
        url: "https://example.com/feed.xml",
        feed_profile: feed_profile,
        feed: feed
      )
      assert result.persisted?
      assert_equal "https://example.com/feed.xml", result.url
      assert_equal feed_profile, result.feed_profile
      assert_equal feed, result.feed
    end
  end

  test "should belong to feed optionally" do
    preview = create(:feed_preview, feed_profile: feed_profile, feed: nil)
    assert_nil preview.feed
    assert preview.valid?

    preview.feed = feed
    assert_equal feed, preview.feed
    assert preview.valid?
  end

  test "for_cache_key scope should find preview by url and feed_profile_id" do
    preview1 = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed1.xml")
    preview2 = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed2.xml")

    result = FeedPreview.for_cache_key("https://example.com/feed1.xml", feed_profile.id)
    assert_includes result, preview1
    assert_not_includes result, preview2
  end

  test "recent scope should order by created_at desc" do
    preview1 = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed1.xml")
    preview2 = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed2.xml")

    # Update timestamps to ensure order
    preview1.update_column(:created_at, 1.hour.ago)
    preview2.update_column(:created_at, 2.hours.ago)

    result = FeedPreview.recent
    assert_equal [preview1, preview2], result.to_a
  end
end
