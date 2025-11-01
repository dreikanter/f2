require "test_helper"

class PostHelperTest < ActionView::TestCase
  include PostHelper
  include TimeHelper

  test "#post_metadata_segments should include feed link when requested" do
    feed = create(:feed, target_group: "testgroup")

    post = create(
      :post,
      :published,
      feed: feed,
      attachment_urls: ["https://example.com/a.png"],
      comments: ["Great post!"],
      source_url: "https://example.com/source",
      freefeed_post_id: "post-123"
    )

    segments = post_metadata_segments(post, show_feed: true, withdraw_allowed: false)

    assert_includes segments.first, feed.name
  end

  test "#post_metadata_segments should build default segments" do
    feed = create(:feed)

    post = create(
      :post,
      :published,
      feed: feed,
      attachment_urls: ["https://example.com/a.png"],
      comments: ["Great post!"],
      source_url: "https://example.com/source"
    )

    segments = post_metadata_segments(post, withdraw_allowed: false)

    assert_includes segments, "Attachments: #{post.attachment_urls.size}"
    assert_includes segments, "Comments: #{post.comments.size}"
    assert segments.any? { |segment| segment.include?("Published") }
  end

  test "#post_metadata_segments should include withdraw link when permitted" do
    feed = create(:feed)

    post = create(
      :post,
      :published,
      feed: feed,
      attachment_urls: ["https://example.com/a.png"],
      comments: ["Great post!"],
      source_url: "https://example.com/source"
    )

    segments = post_metadata_segments(post, withdraw_allowed: true)

    assert segments.any? { |segment| segment.include?("Withdraw") }
  end
end
