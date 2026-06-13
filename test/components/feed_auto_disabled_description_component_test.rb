require "test_helper"
require "view_component/test_case"

class FeedAutoDisabledDescriptionComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user, name: "Test Feed")
  end

  def event(error_count: 10)
    Event.create!(type: "feed_auto_disabled", level: :warning, subject: feed, user: user,
                  message: "", metadata: { error_count: error_count })
  end

  test "#call should append the failure count" do
    result = render_inline(FeedAutoDisabledDescriptionComponent.new(event: event(error_count: 10)))

    assert_includes result.to_html, "turned off"
    assert_equal "(10 failures in a row)", result.css("[data-key='events.error_count']").first&.text
  end

  test "#call should omit the suffix when the count is missing" do
    result = render_inline(FeedAutoDisabledDescriptionComponent.new(event: event(error_count: 0)))

    assert_includes result.to_html, "turned off"
    assert_nil result.css("[data-key='events.error_count']").first
  end
end
