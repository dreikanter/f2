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

  test "should validate presence of feed_profile_key" do
    preview = build(:feed_preview, feed_profile_key: nil, user: user)
    assert_not preview.valid?
    assert preview.errors.of_kind?(:feed_profile_key, :blank)
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

  test ".digest_for should depend only on the profile's source input" do
    same_source = FeedPreview.digest_for("rss", { "url" => "https://x.test" })
    with_extra = FeedPreview.digest_for("rss", { "url" => "https://x.test", "derived" => "anything" })
    assert_equal same_source, with_extra,
                 "non-source params must not change identity"
  end

  test ".digest_for should differ for different source input" do
    refute_equal FeedPreview.digest_for("rss", { "url" => "https://a.test" }),
                 FeedPreview.digest_for("rss", { "url" => "https://b.test" })
  end

  test ".digest_for should read the source key for the profile's input_shape" do
    query_digest = FeedPreview.digest_for("llm_web_search", { "query" => "rust async" })
    # A url key is ignored for a query-shaped profile; the query value drives it.
    assert_equal query_digest,
                 FeedPreview.digest_for("llm_web_search", { "query" => "rust async", "url" => "ignored" })
  end

  test ".fresh_ready should find a ready preview within the window" do
    user = create(:user)
    preview = create(:feed_preview, :completed, user: user,
                     feed_profile_key: "rss", params: { "url" => "https://x.test" })
    preview.update!(ready_at: 1.minute.ago)

    found = FeedPreview.fresh_ready(
      user_id: user.id, feed_profile_key: "rss",
      params: { "url" => "https://x.test" }, within: 60.minutes
    )
    assert_equal preview, found
  end

  test ".fresh_ready should ignore stale or non-ready previews" do
    user = create(:user)
    create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
           params: { "url" => "https://x.test" }, ready_at: 2.hours.ago)

    assert_nil FeedPreview.fresh_ready(
      user_id: user.id, feed_profile_key: "rss",
      params: { "url" => "https://x.test" }, within: 60.minutes
    )
  end
end
