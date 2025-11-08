require "test_helper"
require "view_component/test_case"

class SpinnerComponentTest < ViewComponent::TestCase
  test "should render SVG spinner" do
    result = render_inline(SpinnerComponent.new)

    svg = result.css("svg").first
    assert_not_nil svg
    assert_equal "true", svg["aria-hidden"]
    assert svg["class"].present?
  end

  test "should accept custom parameters" do
    result = render_inline(
      SpinnerComponent.new(
        size: "w-12 h-12",
        color: "text-blue-500",
        fill: "fill-blue-800",
        css_class: "mr-3"
      )
    )

    svg = result.css("svg").first
    assert_not_nil svg
  end
end
