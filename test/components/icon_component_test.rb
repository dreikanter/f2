require "test_helper"
require "view_component/test_case"

class IconComponentTest < ViewComponent::TestCase
  test "renders check-circle icon as inline SVG" do
    result = render_inline(IconComponent.new("check-circle"))

    span = result.css("span").first
    assert_not_nil span
    assert_includes span["class"], "inline-block"

    svg = span.css("svg").first
    assert_not_nil svg
    assert_equal "currentColor", svg["fill"]
    assert_equal "0 0 16 16", svg["viewBox"]
  end

  test "renders x-circle icon as inline SVG" do
    result = render_inline(IconComponent.new("x-circle"))

    svg = result.css("svg").first
    assert_not_nil svg
    assert_equal "currentColor", svg["fill"]
  end

  test "applies custom CSS classes" do
    result = render_inline(IconComponent.new("check-circle", css_class: "h-5 w-5 text-green-600"))

    span = result.css("span").first
    assert_includes span["class"], "h-5"
    assert_includes span["class"], "w-5"
    assert_includes span["class"], "text-green-600"
    assert_includes span["class"], "inline-block"
  end

  test "sets aria-hidden by default" do
    result = render_inline(IconComponent.new("check-circle"))

    span = result.css("span").first
    assert_equal "true", span["aria-hidden"]
  end

  test "allows aria-label override" do
    result = render_inline(IconComponent.new("check-circle", aria_hidden: false, aria_label: "Success"))

    span = result.css("span").first
    assert_nil span["aria-hidden"]
    assert_equal "Success", span["aria-label"]
  end

  test "returns fallback icon for unknown icon name" do
    result = render_inline(IconComponent.new("unknown-icon"))

    svg = result.css("svg").first
    assert_not_nil svg
    # Fallback is a simple circle
    circle = svg.css("circle").first
    assert_not_nil circle
  end
end
