require "test_helper"
require "view_component/test_case"

class SpinnerComponentTest < ViewComponent::TestCase
  test "should render SVG spinner" do
    result = render_inline(SpinnerComponent.new)

    assert result.css("svg")
  end

  test "should accept custom parameters" do
    result = render_inline(SpinnerComponent.new(css_class: "test"))
    svg = result.css("svg").first

    assert_includes svg["class"], "test"
  end

  test "should render intrinsic width and height so it stays sized without CSS" do
    result = render_inline(SpinnerComponent.new)
    svg = result.css("svg").first

    assert_equal "32", svg["width"]
    assert_equal "32", svg["height"]
  end
end
