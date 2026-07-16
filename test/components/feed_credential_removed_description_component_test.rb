require "test_helper"
require "view_component/test_case"

class FeedCredentialRemovedDescriptionComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user, name: "Test Feed")
  end

  test "renders AI credential removal as the reason an enabled feed was disabled" do
    event = Event.create!(
      type: AiCredential::REMOVED_EVENT_TYPE,
      level: :warning,
      subject: feed,
      user: user,
      metadata: { disabled: true }
    )

    result = render_inline(EventDescriptionComponent.for(event)).to_html

    assert_includes result, "Test Feed"
    assert_includes result, "/feeds/#{feed.id}"
    assert_includes result, "was disabled because its AI credentials were removed"
  end

  test "does not claim an already-inactive feed was disabled by search credential removal" do
    event = Event.create!(
      type: SearchCredential::REMOVED_EVENT_TYPE,
      level: :warning,
      subject: feed,
      user: user,
      metadata: { disabled: false }
    )

    result = render_inline(EventDescriptionComponent.for(event)).to_html

    assert_includes result, "Test Feed"
    assert_includes result, "search credentials were removed"
    assert_not_includes result, "was disabled"
  end
end
