require "test_helper"
require "view_component/test_case"

class StatListItemComponentTest < ViewComponent::TestCase
  test "#render should render label and value" do
    result = render_inline(StatListItemComponent.new(label: "Posts", value: "42"))

    assert_equal "Posts", result.at_css("dt").text
    assert_equal "42", result.at_css("dd").text
  end

  test "#render should attach key data attributes when key is given" do
    result = render_inline(StatListItemComponent.new(label: "Posts", value: "42", key: "stats.posts"))

    assert_equal "stats.posts", result.at_css("div")["data-key"]
    assert_equal "stats.posts.label", result.at_css("dt")["data-key"]
    assert_equal "stats.posts.value", result.at_css("dd")["data-key"]
  end

  test "#render should omit data attributes when key is nil" do
    result = render_inline(StatListItemComponent.new(label: "Posts", value: "42"))

    assert_nil result.at_css("div")["data-key"]
    assert_nil result.at_css("dt")["data-key"]
    assert_nil result.at_css("dd")["data-key"]
  end

  test "#render should apply muted style to value when muted is true" do
    result = render_inline(StatListItemComponent.new(label: "Posts", value: "42", muted: true))

    assert_includes result.at_css("dd")["class"], "text-slate-500"
    assert_not_includes result.at_css("dd")["class"], "text-slate-900"
  end

  test "#render should apply default style to value when muted is false" do
    result = render_inline(StatListItemComponent.new(label: "Posts", value: "42", muted: false))

    assert_includes result.at_css("dd")["class"], "text-slate-900"
    assert_not_includes result.at_css("dd")["class"], "text-slate-500"
  end

  test "#render should use list item CSS classes" do
    result = render_inline(StatListItemComponent.new(label: "Posts", value: "42"))

    assert_includes result.at_css("div")["class"], "flex"
    assert_includes result.at_css("div")["class"], "items-baseline"
    assert_includes result.at_css("div")["class"], "justify-between"
  end
end
