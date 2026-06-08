require "test_helper"
require "view_component/test_case"

class PostDeleteModalComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user)
  end

  def post
    @post ||= create(:post, :published, feed: feed)
  end

  test "#render should check Freefeed deletion by default and leave the record off" do
    result = render_inline PostDeleteModalComponent.new(post: post)

    assert result.at_css("input[name='delete_freefeed_post']")[:checked]
    assert_nil result.at_css("input[name='delete_record']")[:checked]
  end

  test "#render should post a delete request to the post path" do
    result = render_inline PostDeleteModalComponent.new(post: post)

    form = result.at_css("form")
    assert_equal "/posts/#{post.id}", form[:action]
    assert_not_nil form.at_css("input[name='_method'][value='delete']")
  end

  test "#render should disable turbo when requested" do
    result = render_inline PostDeleteModalComponent.new(post: post, turbo: false)

    assert_equal "false", result.at_css("form")["data-turbo"]
  end

  test "#render should offer only the record option for a withdrawn post" do
    withdrawn_post = create(:post, feed: feed, status: :withdrawn)
    result = render_inline PostDeleteModalComponent.new(post: withdrawn_post)

    assert_nil result.at_css("input[name='delete_freefeed_post']")
    assert result.at_css("input[name='delete_record']")[:checked]
  end

  test "#render should offer only the record option for a failed post" do
    failed_post = create(:post, :failed, feed: feed)
    result = render_inline PostDeleteModalComponent.new(post: failed_post)

    assert_nil result.at_css("input[name='delete_freefeed_post']")
    assert result.at_css("input[name='delete_record']")[:checked]
    assert_includes result.text, "never made it to FreeFeed"
  end

  test "#render should wire the submit button to the post-delete controller" do
    result = render_inline PostDeleteModalComponent.new(post: post)

    submit = result.at_css("input[type='submit'][data-post-delete-target='submit']")
    assert_not_nil submit
  end
end
