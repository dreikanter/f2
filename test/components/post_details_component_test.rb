require "test_helper"
require "view_component/test_case"

class PostDetailsComponentTest < ViewComponent::TestCase
  def feed
    @feed ||= create(:feed)
  end

  test "#render should show the reposted time for published posts" do
    post = create(:post, :published, feed: feed, published_at: 1.day.ago, updated_at: 1.hour.ago)

    result = render_inline(PostDetailsComponent.new(post: post))

    assert_equal 1, result.css("dl").size
    assert_empty result.css("ul")
    assert_not_empty result.css("dl > div > dt")
    assert_equal result.css("dl > div > dt").size, result.css("dl > div > dd").size

    assert_equal %w[post.feed post.published post.reposted post.source_url post.uid post.freefeed_post_id],
                 row_keys(result)

    assert_not_nil result.css('[data-key="post.reposted"]').first
    assert_includes result.css('[data-key="post.reposted.label"]').first.text, "Reposted"
  end

  test "#render should not show the reposted field for unpublished posts" do
    post = create(:post, feed: feed, status: :draft)

    result = render_inline(PostDetailsComponent.new(post: post))

    assert_equal %w[post.feed post.published post.source_url post.uid],
                 row_keys(result)
  end

  test "#render should show validation errors between the source URL and UID" do
    post = create(:post, feed: feed, status: :rejected, validation_errors: ["no_images"])

    result = render_inline(PostDetailsComponent.new(post: post))

    assert_equal %w[post.feed post.published post.source_url post.validation_errors post.uid],
                 row_keys(result)
    assert_equal ["no_images"], result.css('[data-key="post.validation_errors.value"] li').map(&:text)
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

  test "#render should link the FreeFeed post ID to its stored URL" do
    post = create(:post, :published, feed: feed)

    result = render_inline(PostDetailsComponent.new(post: post))

    link = result.css('[data-key="post.freefeed_post_id.value"] a').first
    assert_not_nil link
    assert_equal post.freefeed_post_url, link["href"]
  end

  test "#render should show the FreeFeed post ID unlinked when no URL was stored" do
    post = create(:post, :published, feed: feed, freefeed_post_url: nil)

    result = render_inline(PostDetailsComponent.new(post: post))

    assert_nil result.css('[data-key="post.freefeed_post_id.value"] a').first
  end

  private

  def row_keys(result)
    result.css('[data-key^="post."]:not([data-key$=".label"]):not([data-key$=".value"])')
          .map { |row| row["data-key"] }
  end
end
