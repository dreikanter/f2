require "test_helper"
require "view_component/test_case"

class FeedPostCommentsFailedEventTest < ViewComponent::TestCase
  test "the event should explain that the post still published" do
    user = create(:user)
    feed = create(:feed, user: user, name: "Test Feed")
    event = Event.create!(
      type: "feed_post_comments_failed",
      level: :error,
      subject: feed,
      user: user,
      message: "internal provider details"
    )

    result = render_inline(EventDescriptionComponent.for(event)).to_html

    assert_includes result, "Test Feed"
    assert_includes result, "published a post, but some comments couldn't be added"
    assert_not_includes result, "internal provider details"
  end
end
