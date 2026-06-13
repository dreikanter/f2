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
    assert post.errors.of_kind?(:uid, :blank)
  end

  test "should require uid to be unique within feed scope" do
    post1 = create(:post, feed: feed, uid: "duplicate-uid")
    post2 = build(:post, feed: feed, uid: "duplicate-uid")

    assert_not post2.valid?
    assert post2.errors.of_kind?(:uid, :taken)
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
    assert post.errors.of_kind?(:published_at, :blank)
  end

  test "should require source_url" do
    post = build(:post, source_url: nil)
    assert_not post.valid?
    assert post.errors.of_kind?(:source_url, :blank)
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

  test "#freefeed_url should return the full URL when all parts are present" do
    post = create(:post, :published, feed: feed, freefeed_post_id: "abc123")

    assert_equal "#{feed.access_token.host}/testgroup/abc123", post.freefeed_url
  end

  test "#freefeed_url should return nil when freefeed_post_id is blank" do
    post = create(:post, :published, feed: feed, freefeed_post_id: nil)

    assert_nil post.freefeed_url
  end

  test "#freefeed_url should return nil when target_group is blank" do
    feed_no_group = create(:feed, target_group: "")
    post = create(:post, :published, feed: feed_no_group, freefeed_post_id: "abc123")

    assert_nil post.freefeed_url
  end

  test "should allow nil freefeed_post_id" do
    post = build(:post, freefeed_post_id: nil)
    assert post.valid?
  end

  test "#reposted_at should hold the repost moment for published posts" do
    post = create(:post, :published, feed: feed, feed_entry: feed_entry, reposted_at: 1.hour.ago)

    assert_in_delta 1.hour.ago.to_i, post.reposted_at.to_i, 1
  end

  test "#reposted_at should be nil for posts that have not been reposted" do
    post = create(:post, feed: feed, feed_entry: feed_entry, status: :draft)

    assert_nil post.reposted_at
  end

  test "should validate content length within FreeFeed limits when enqueued" do
    post = build(:post, :enqueued, content: "a" * Post::MAX_CONTENT_LENGTH)
    assert post.valid?

    post = build(:post, :enqueued, content: "a" * (Post::MAX_CONTENT_LENGTH + 1))
    assert_not post.valid?
    assert post.errors.of_kind?(:content, :too_long)
  end

  test "should validate comments length within FreeFeed limits when enqueued" do
    valid_comment = "a" * Post::MAX_COMMENT_LENGTH
    post = build(:post, :enqueued, comments: [valid_comment])
    assert post.valid?

    long_comment = "a" * (Post::MAX_COMMENT_LENGTH + 1)
    post = build(:post, :enqueued, comments: [long_comment])
    assert_not post.valid?
    assert_includes post.errors[:comments], "Comment 1 exceeds maximum length of #{Post::MAX_COMMENT_LENGTH} characters"
  end

  test "should validate multiple comments length when enqueued" do
    valid_comment = "a" * Post::MAX_COMMENT_LENGTH
    long_comment = "a" * (Post::MAX_COMMENT_LENGTH + 1)

    post = build(:post, :enqueued, comments: [valid_comment, long_comment, valid_comment])
    assert_not post.valid?
    assert_includes post.errors[:comments], "Comment 2 exceeds maximum length of #{Post::MAX_COMMENT_LENGTH} characters"
  end

  test "should handle non-string comments gracefully" do
    post = build(:post, :enqueued, comments: ["valid", nil, 123, "also valid"])
    assert post.valid?
  end

  test "should not enforce length limits when leaving the queue" do
    over_content = "a" * (Post::MAX_CONTENT_LENGTH + 1)
    over_comment = "a" * (Post::MAX_COMMENT_LENGTH + 1)

    %i[published failed withdrawn].each do |status|
      post = build(:post, status: status, content: over_content, comments: [over_comment])
      assert post.valid?, "expected #{status} post to skip length limits, got: #{post.errors.full_messages}"
    end
  end

  test ".clamp_comment should truncate text over the FreeFeed limit" do
    long = "a" * (Post::MAX_COMMENT_LENGTH + 100)
    clamped = Post.clamp_comment(long)

    assert_equal Post::MAX_COMMENT_LENGTH, clamped.length
    assert clamped.end_with?("…")
  end

  test ".clamp_comment should leave text within the limit untouched" do
    text = "a" * Post::MAX_COMMENT_LENGTH
    assert_equal text, Post.clamp_comment(text)
  end

  test ".clamp_comment should pass non-string values through unchanged" do
    assert_nil Post.clamp_comment(nil)
    assert_equal 123, Post.clamp_comment(123)
  end

  test "#normalized_attributes should include only normalized fields" do
    post = build(:post,
      uid: "test-uid",
      content: "test content",
      source_url: "https://example.com",
      attachment_urls: ["https://example.com/image.jpg"],
      comments: ["test comment"],
      status: :enqueued,
      validation_errors: []
    )

    expected = {
      "uid" => "test-uid",
      "published_at" => post.published_at.as_json,
      "source_url" => "https://example.com",
      "content" => "test content",
      "attachment_urls" => ["https://example.com/image.jpg"],
      "comments" => ["test comment"],
      "status" => "enqueued",
      "validation_errors" => []
    }

    assert_equal expected, post.normalized_attributes
  end

  test "should not allow enqueued status with validation errors" do
    post = build(:post, feed: feed, feed_entry: feed_entry, status: :enqueued, validation_errors: ["url_too_long"])

    assert_not post.valid?
    assert_includes post.errors[:status], "cannot be enqueued when validation_errors is not empty"
  end

  test "should allow enqueued status with empty validation errors" do
    post = build(:post, feed: feed, feed_entry: feed_entry, status: :enqueued, validation_errors: [])

    assert post.valid?
  end

  test "should allow rejected status with validation errors" do
    post = build(:post, feed: feed, feed_entry: feed_entry, status: :rejected, validation_errors: ["url_too_long"])

    assert post.valid?
  end
end
