require "test_helper"

class PostHelperTest < ActionView::TestCase
  include PostHelper
  include TimeHelper

  def policy(record)
    Pundit.policy!(Current.user, record)
  end

  test "post_metadata_segments includes feed link when requested" do
    post, feed = build_post_for_metadata(with_links: true)

    original_session = Current.session
    Current.session = create(:session, user: feed.user)
    segments = post_metadata_segments(post, show_feed: true)
    assert_includes segments.first, feed.name
  ensure
    Current.session = original_session
  end

  test "post_metadata_segments builds default segments" do
    post, feed = build_post_for_metadata

    original_session = Current.session
    Current.session = create(:session, user: feed.user)
    segments = post_metadata_segments(post)
    assert_includes segments, "Attachments: #{post.attachment_urls.size}"
    assert_includes segments, "Comments: #{post.comments.size}"
    assert segments.any? { |segment| segment.include?("Published") }
  ensure
    Current.session = original_session
  end

  test "post_metadata_segments includes withdraw link when permitted" do
    post, feed = build_post_for_metadata

    policy = Minitest::Mock.new
    policy.expect(:destroy?, true)

    original_session = Current.session
    Current.session = create(:session, user: feed.user)
    Pundit.stub(:policy, policy) do
      segments = post_metadata_segments(post)
      assert segments.any? { |segment| segment.include?("Withdraw") }
    end
  ensure
    Current.session = original_session
  end

  private

  def build_post_for_metadata(with_links: false)
    feed = create(:feed)
    post = create(:post,
                  :published,
                  feed: feed,
                  attachment_urls: ["https://example.com/a.png"],
                  comments: ["Great post!"],
                  source_url: "https://example.com/source")

    if with_links
      feed.update!(target_group: feed.target_group.presence || "testgroup")
      feed.access_token.update!(host: "https://freefeed.test") if feed.access_token
      post.update!(freefeed_post_id: "post-123")
    end

    [post, feed]
  end
end
