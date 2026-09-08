require "test_helper"
require "view_component/test_case"

class FreefeedInstanceBadgeComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def token(host)
    create(:access_token, user: user, host: host)
  end

  test "#render should mark candy in orange" do
    result = render_inline(FreefeedInstanceBadgeComponent.new(access_token: token("https://candy.freefeed.net")))

    badge = result.at_css("span")
    assert_equal "candy", badge.text
    assert_includes badge["class"], "bg-candy-subtle"
    assert_includes badge["class"], "text-candy-strong"
  end

  test "#render should mark beta in blue" do
    result = render_inline(FreefeedInstanceBadgeComponent.new(access_token: token("https://beta.freefeed.net")))

    badge = result.at_css("span")
    assert_equal "beta", badge.text
    assert_includes badge["class"], "bg-beta-subtle"
    assert_includes badge["class"], "text-beta-strong"
  end

  test "#render should use the small badge size" do
    result = render_inline(FreefeedInstanceBadgeComponent.new(access_token: token("https://candy.freefeed.net")))

    assert_includes result.at_css("span")["class"], "px-1.5 py-0.5"
  end

  test "#render should fall back to neutral for an unfamiliar instance" do
    result = render_inline(FreefeedInstanceBadgeComponent.new(access_token: token("https://gamma.freefeed.net")))

    badge = result.at_css("span")
    assert_equal "gamma", badge.text
    assert_includes badge["class"], "bg-surface-muted"
  end

  test "#render should render nothing for the main FreeFeed instance" do
    result = render_inline(FreefeedInstanceBadgeComponent.new(access_token: token("https://freefeed.net")))

    assert_empty result.css("span")
  end

  test "#render should render nothing without a token" do
    result = render_inline(FreefeedInstanceBadgeComponent.new(access_token: nil))

    assert_empty result.css("span")
  end

  test "#render should set data-key when key is given" do
    result = render_inline(FreefeedInstanceBadgeComponent.new(access_token: token("https://candy.freefeed.net"), key: "feed.1.instance"))

    assert_not_nil result.at_css("[data-key='feed.1.instance']")
  end
end
