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

  test "#call should set data-key when key is given" do
    result = render_inline(BadgeComponent.new(text: "Enabled", color: :success, key: "feed.1.enabled_badge"))

    assert_not_nil result.at_css("[data-key='feed.1.enabled_badge']")
  end

  test "#call should omit data-key when key is missing" do
    result = render_inline(BadgeComponent.new(text: "Enabled", color: :success))

    assert_nil result.at_css("span")["data-key"]
  end
end
