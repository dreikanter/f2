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

  test "#params_digest should be stable regardless of key order" do
    a = build(:feed_preview, params: { "url" => "https://x.test", "extra" => "1" })
    b = build(:feed_preview, params: { "extra" => "1", "url" => "https://x.test" })
    assert_equal a.params_digest, b.params_digest
  end

  test "#params_digest should be stable regardless of nested key order" do
    a = FeedPreview.digest_for({ "outer" => { "b" => 2, "a" => 1 }, "z" => "x" })
    b = FeedPreview.digest_for({ "z" => "x", "outer" => { "a" => 1, "b" => 2 } })
    assert_equal a, b
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
