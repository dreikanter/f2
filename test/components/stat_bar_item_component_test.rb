require "test_helper"
require "view_component/test_case"

class StatBarItemComponentTest < ViewComponent::TestCase
  test "#render should render label and value" do
    result = render_inline(StatBarItemComponent.new(label: "Active", value: "38"))

    assert_equal "Active", result.at_css("dt").text
    assert_equal "38", result.at_css("dd").text
  end

  test "#render should use bar item CSS classes" do
    result = render_inline(StatBarItemComponent.new(label: "Active", value: "38"))

    assert_includes result.at_css("div")["class"], "flex-col-reverse"
    assert_includes result.at_css("dd")["class"], "text-2xl"
  end

  test "#render should attach key data attributes when key is given" do
    result = render_inline(StatBarItemComponent.new(label: "Active", value: "38", key: "stats.active"))

    assert_equal "stats.active", result.at_css("div")["data-key"]
    assert_equal "stats.active.label", result.at_css("dt")["data-key"]
    assert_equal "stats.active.value", result.at_css("dd")["data-key"]
  end

  test "#render should apply muted style to value when muted is true" do
    result = render_inline(StatBarItemComponent.new(label: "Active", value: "38", muted: true))

    assert_includes result.at_css("dd")["class"], "text-muted"
    assert_not_includes result.at_css("dd")["class"], "text-heading"
  end

  test "#render should show a muted dash for a blank value" do
    result = render_inline(StatBarItemComponent.new(label: "Recent", value: nil))

    assert_equal StatItemComponent::BLANK_VALUE, result.at_css("dd").text
    assert_includes result.at_css("dd")["class"], "text-2xl font-semibold whitespace-nowrap"
    assert_includes result.at_css("dd")["class"], "text-muted"
  end

  test "#render should expose the tooltip as tippy content" do
    result = render_inline(StatBarItemComponent.new(label: "Active", value: "38", tooltip: "Active feeds"))

    assert_equal "Active feeds", result.at_css("div")["data-tippy-content"]
  end

  test "#render should omit tippy content when no tooltip is given" do
    result = render_inline(StatBarItemComponent.new(label: "Active", value: "38"))

    assert_nil result.at_css("div")["data-tippy-content"]
  end
end
