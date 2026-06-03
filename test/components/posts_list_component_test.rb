require "test_helper"
require "view_component/test_case"

class PostsListComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user)
  end

  test "#render should render an item for each post" do
    post = create(:post, feed: feed)
    result = render_inline PostsListComponent.new(posts: [post])

    assert_not_empty result.css("##{ActionView::RecordIdentifier.dom_id(post)}")
  end

  test "#render should not render an empty state when there are no posts" do
    result = render_inline PostsListComponent.new(posts: [])

    assert_empty result.css('[data-key="empty-state"]')
    assert_empty result.css(".border-dashed")
    assert_not_includes result.text, "No posts"
  end
end
