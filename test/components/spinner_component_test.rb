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
end
