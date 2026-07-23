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

  test "#render should render a view all row as the last list item when url is given" do
    post = create(:post, feed: feed)
    result = render_inline PostsListComponent.new(posts: [post], view_all_url: "/posts")

    link = result.at_css("li:last-child a[data-key='posts.view_all']")
    assert_not_nil link
    assert_equal "/posts", link["href"]
    assert_equal "View all", link.text
  end

  test "#render should omit the view all row when no url is given" do
    post = create(:post, feed: feed)
    result = render_inline PostsListComponent.new(posts: [post])

    assert_empty result.css("[data-key='posts.view_all']")
  end

  test "#render should not render an empty state when there are no posts" do
    result = render_inline PostsListComponent.new(posts: [])

    assert_empty result.css('[data-key="empty-state"]')
    assert_empty result.css(".border-dashed")
    assert_not_includes result.text, "No posts"
  end
end
