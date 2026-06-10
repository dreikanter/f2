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

  test "#render should apply a shadow to the details list" do
    post = create(:post, feed: feed)

    result = render_inline(PostDetailsComponent.new(post: post))

    assert_includes result.css("ul").first["class"], "shadow-sm"
  end
end
