require "test_helper"
require "view_component/test_case"

class SpinnerComponentTest < ViewComponent::TestCase
  test "renders SVG spinner with default styling" do
    result = render_inline(SpinnerComponent.new)

    svg = result.css("svg").first
    assert_not_nil svg
    assert_equal "true", svg["aria-hidden"]
    assert_includes svg["class"], "w-8"
    assert_includes svg["class"], "h-8"
    assert_includes svg["class"], "animate-spin"
    assert_includes svg["class"], "text-gray-300"
    assert_includes svg["class"], "fill-cyan-600"
  end

  test "applies custom size classes" do
    result = render_inline(SpinnerComponent.new(size: "w-12 h-12"))

    svg = result.css("svg").first
    assert_includes svg["class"], "w-12"
    assert_includes svg["class"], "h-12"
  end

  test "applies custom color classes" do
    result = render_inline(SpinnerComponent.new(color: "text-blue-500", fill: "fill-blue-800"))

    svg = result.css("svg").first
    assert_includes svg["class"], "text-blue-500"
    assert_includes svg["class"], "fill-blue-800"
  end

  test "merges additional CSS classes" do
    result = render_inline(SpinnerComponent.new(css_class: "mr-3"))

    svg = result.css("svg").first
    assert_includes svg["class"], "mr-3"
    assert_includes svg["class"], "animate-spin"
  end
end
