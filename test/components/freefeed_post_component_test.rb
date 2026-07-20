require "test_helper"
require "view_component/test_case"

class FreefeedPostComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def feed
    @feed ||= create(:feed, user: user, access_token: access_token, target_group: "testgroup")
  end

  test "#render should show the author and the target group in the header" do
    post = create(:post, feed: feed)

    result = render_inline(FreefeedPostComponent.new(post: post))

    assert_includes result.css('[data-key="freefeed_post.author"]').first.text, "testuser"
    group = result.css('[data-key="freefeed_post.group"]').first
    assert_equal "testgroup", group.text
    assert_equal "#{access_token.host}/testgroup", group["href"]
  end

  test "#render should fall back to a generic author without an access token" do
    post = create(:post, feed: create(:feed, :without_access_token, user: user))

    result = render_inline(FreefeedPostComponent.new(post: post))

    assert_equal "You", result.css('[data-key="freefeed_post.author"]').first.text
    assert_empty result.css('[data-key="freefeed_post.group"]')
  end

  test "#render should show the post content with linkified URLs" do
    post = create(:post, feed: feed, content: "Interesting story - https://example.com/story")

    result = render_inline(FreefeedPostComponent.new(post: post))

    content = result.css('[data-key="freefeed_post.content"]').first
    assert_includes content.text, "Interesting story"
    assert_equal "https://example.com/story", content.css("a").first["href"]
  end

  test "#render should show a relative timestamp in the footer" do
    post = create(:post, feed: feed, published_at: 6.minutes.ago)

    result = render_inline(FreefeedPostComponent.new(post: post))

    assert_includes result.css('[data-key="freefeed_post.timestamp"] time').first.text, "6 minutes ago"
  end

  test "#render should link the timestamp to the published FreeFeed post" do
    post = create(:post, :published, feed: feed)

    result = render_inline(FreefeedPostComponent.new(post: post))

    link = result.css('a[data-key="freefeed_post.timestamp"]').first
    assert_equal post.freefeed_url, link["href"]
  end

  test "#render should keep the action links decorative" do
    post = create(:post, feed: feed)

    result = render_inline(FreefeedPostComponent.new(post: post))

    actions = result.css('[data-key="freefeed_post.actions"]').first
    assert_equal "true", actions["aria-hidden"]
    assert_includes actions.text, "Comment"
    assert_empty actions.css("a")
  end

  test "#render should show attachment thumbnails with filename alt text" do
    post = create(:post, :with_attachments, feed: feed)

    result = render_inline(FreefeedPostComponent.new(post: post))

    attachments = result.css('[data-key="freefeed_post.attachments"]').first
    assert_equal "image1.jpg", attachments.css("img").first["alt"]
    assert_equal 2, attachments.css("a").size
  end

  test "#render should fall back to a generic alt for unparseable attachment URLs" do
    post = create(:post, feed: feed, attachment_urls: ["https://example.com/bad path.jpg"])

    result = render_inline(FreefeedPostComponent.new(post: post))

    assert_equal "Attachment", result.css('[data-key="freefeed_post.attachments"] img').first["alt"]
  end

  test "#render should show comments" do
    post = create(:post, :with_comments, feed: feed)

    result = render_inline(FreefeedPostComponent.new(post: post))

    comments = result.css('[data-key="freefeed_post.comment"]')
    assert_equal 1, comments.size
    assert_includes comments.first.text, "Additional context about this post"
  end

  test "#render should not show attachment or comment sections when empty" do
    post = create(:post, feed: feed)

    result = render_inline(FreefeedPostComponent.new(post: post))

    assert_empty result.css('[data-key="freefeed_post.attachments"]')
    assert_empty result.css('[data-key="freefeed_post.comments"]')
  end
end
