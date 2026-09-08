require "test_helper"
require "view_component/test_case"

class BadgeComponentTest < ViewComponent::TestCase
  test "#call should render text with badge styling" do
    result = render_inline(BadgeComponent.new(text: "Enabled", color: :success))

    badge = result.at_css("span")
    assert_equal "Enabled", badge.text
    assert_includes badge["class"], "ring-1 ring-inset"
    assert_includes badge["class"], "bg-success-subtle"
    assert_includes badge["class"], "text-success-strong"
  end

  test "#call should default to neutral color" do
    result = render_inline(BadgeComponent.new(text: "Draft"))

    assert_includes result.at_css("span")["class"], "bg-surface-muted"
  end

  test "#call should fall back to neutral for unknown color" do
    result = render_inline(BadgeComponent.new(text: "Draft", color: :chartreuse))

    assert_includes result.at_css("span")["class"], "bg-surface-muted"
  end

  test "#call should style candy and beta with their instance colors" do
    candy = render_inline(BadgeComponent.new(text: "candy", color: :candy)).at_css("span")
    beta = render_inline(BadgeComponent.new(text: "beta", color: :beta)).at_css("span")

    assert_includes candy["class"], "bg-candy-subtle"
    assert_includes candy["class"], "text-candy-strong"
    assert_includes beta["class"], "bg-beta-subtle"
    assert_includes beta["class"], "text-beta-strong"
  end

  test "#call should default to the regular size" do
    result = render_inline(BadgeComponent.new(text: "Enabled"))

    assert_includes result.at_css("span")["class"], "px-2 py-1"
  end

  test "#call should render the small size without the regular padding" do
    result = render_inline(BadgeComponent.new(text: "candy", size: :sm))

    badge = result.at_css("span")
    assert_includes badge["class"], "px-1.5 py-0.5"
    assert_not_includes badge["class"], "py-1 "
  end

  test "#call should fall back to the regular size for unknown size" do
    result = render_inline(BadgeComponent.new(text: "Enabled", size: :huge))

    assert_includes result.at_css("span")["class"], "px-2 py-1"
  end

  test "#call should set data-key when key is given" do
    result = render_inline(BadgeComponent.new(text: "Enabled", color: :success, key: "feed.1.enabled_badge"))

    assert_not_nil result.at_css("[data-key='feed.1.enabled_badge']")
  end

  test "#call should omit data-key when key is missing" do
    result = render_inline(BadgeComponent.new(text: "Enabled", color: :success))

    assert_nil result.at_css("span")["data-key"]
  end

  test "#call should render extra data attributes alongside the key" do
    result = render_inline(BadgeComponent.new(text: "Valid", color: :success, key: "access_token.active", data: { status: "active" }))

    badge = result.at_css("span")
    assert_equal "active", badge["data-status"]
    assert_equal "access_token.active", badge["data-key"]
  end
end
