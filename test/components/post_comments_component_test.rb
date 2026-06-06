require "test_helper"
require "view_component/test_case"

class PostCommentsComponentTest < ViewComponent::TestCase
  def feed
    @feed ||= create(:feed)
  end

  test "#render should show comments when present" do
    post = create(:post, :with_comments, feed: feed)

    result = render_inline(PostCommentsComponent.new(post: post))

    assert_not_nil result.css('[data-key="post.comments"]').first
    assert_includes result.text, "Additional context about this post"
  end

  test "#render should not render when there are no comments" do
    post = create(:post, feed: feed)

    result = render_inline(PostCommentsComponent.new(post: post))

    assert_empty result.css('[data-key="post.comments"]')
  end
end
