require "test_helper"

class PostTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed)
  end

  def feed_entry
    @feed_entry ||= create(:feed_entry, feed: feed)
  end

  def valid_post
    @valid_post ||= build(:post, feed: feed, feed_entry: feed_entry)
  end

  test "should be valid with valid attributes" do
    post = valid_post
    assert post.valid?
  end

  test "should require uid" do
    post = build(:post, uid: nil)
    assert_not post.valid?
    assert_includes post.errors[:uid], "can't be blank"
  end

  test "should require uid to be unique within feed scope" do
    post1 = create(:post, feed: feed, uid: "duplicate-uid")
    post2 = build(:post, feed: feed, uid: "duplicate-uid")

    assert_not post2.valid?
    assert_includes post2.errors[:uid], "has already been taken"
  end

  test "should allow same uid across different feeds" do
    feed2 = create(:feed)
    post1 = create(:post, feed: feed, uid: "same-uid")
    post2 = build(:post, feed: feed2, uid: "same-uid")

    assert post2.valid?
  end

  test "should require published_at" do
    post = build(:post, published_at: nil)
    assert_not post.valid?
    assert_includes post.errors[:published_at], "can't be blank"
  end

  test "should require source_url" do
    post = build(:post, source_url: nil)
    assert_not post.valid?
    assert_includes post.errors[:source_url], "can't be blank"
  end

  test "should allow empty content" do
    post = build(:post, content: "")
    assert post.valid?
  end

  test "should belong to feed" do
    post = valid_post
    assert_respond_to post, :feed
    assert_equal feed, post.feed
  end

  test "should belong to feed_entry" do
    post = valid_post
    assert_respond_to post, :feed_entry
    assert_equal feed_entry, post.feed_entry
  end

  test "should have draft status by default" do
    post = Post.new
    assert_equal "draft", post.status
  end

  test "should have valid enum statuses" do
    post = valid_post

    post.status = :draft
    assert post.draft?
    assert_equal "draft", post.status

    post.status = :enqueued
    assert post.enqueued?
    assert_equal "enqueued", post.status

    post.status = :rejected
    assert post.rejected?
    assert_equal "rejected", post.status

    post.status = :published
    assert post.published?
    assert_equal "published", post.status

    post.status = :failed
    assert post.failed?
    assert_equal "failed", post.status
  end

  test "should serialize attachment_urls as JSON array" do
    urls = ["https://example.com/image1.jpg", "https://example.com/image2.png"]
    post = create(:post, attachment_urls: urls)

    saved_post = Post.find(post.id)
    assert_equal urls, saved_post.attachment_urls
  end

  test "should serialize comments as JSON array" do
    comments = ["First comment", "Second comment"]
    post = create(:post, comments: comments)

    saved_post = Post.find(post.id)
    assert_equal comments, saved_post.comments
  end

  test "should serialize validation_errors as JSON array" do
    errors = ["blank_text", "invalid_link"]
    post = create(:post, validation_errors: errors)

    saved_post = Post.find(post.id)
    assert_equal errors, saved_post.validation_errors
  end

  test "should handle array fields" do
    post = build(:post, attachment_urls: ["url1"], comments: ["comment1"], validation_errors: ["error1"])
    assert_equal ["url1"], post.attachment_urls
    assert_equal ["comment1"], post.comments
    assert_equal ["error1"], post.validation_errors
  end

  test "should allow nil freefeed_post_id" do
    post = build(:post, freefeed_post_id: nil)
    assert post.valid?
  end
end
