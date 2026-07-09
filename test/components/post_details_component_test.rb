require "test_helper"
require "view_component/test_case"

class PostDetailsComponentTest < ViewComponent::TestCase
  def feed
    @feed ||= create(:feed)
  end

  test "#render should show the reposted time for published posts" do
    post = create(:post, :published, feed: feed, published_at: 1.day.ago, updated_at: 1.hour.ago)

    result = render_inline(PostDetailsComponent.new(post: post))

    assert_not_nil result.css('[data-key="post.reposted"]').first
    assert_includes result.css('[data-key="post.reposted.label"]').first.text, "Reposted"
  end

  test "#render should not show the reposted field for unpublished posts" do
    post = create(:post, feed: feed, status: :draft)

    result = render_inline(PostDetailsComponent.new(post: post))

    assert_nil result.css('[data-key="post.reposted"]').first
  end

  test "#render should truncate the source URL instead of overflowing" do
    post = create(:post, feed: feed, source_url: "https://example.com/#{'a' * 200}")

    result = render_inline(PostDetailsComponent.new(post: post))

    link = result.css('[data-key="post.source_url.value"] div.truncate a').first
    assert_not_nil link
    assert_equal post.source_url, link["title"]
  end

  test "#render should truncate the UID and expose the full value in a title" do
    post = create(:post, feed: feed, uid: "uid-#{'b' * 200}")

    result = render_inline(PostDetailsComponent.new(post: post))

    code = result.css('[data-key="post.uid.value"] div.truncate code').first
    assert_not_nil code
    assert_equal post.uid, code["title"]
  end

  test "#render should truncate the FreeFeed post ID" do
    post = create(:post, :published, feed: feed)

    result = render_inline(PostDetailsComponent.new(post: post))

    assert_not_nil result.css('[data-key="post.freefeed_post_id.value"] div.truncate').first
  end
end
