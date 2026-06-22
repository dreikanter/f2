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
end
