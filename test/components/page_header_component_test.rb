require "test_helper"
require "view_component/test_case"

class PageHeaderComponentTest < ViewComponent::TestCase
  test "#render should render title without surrounding whitespace" do
    result = render_inline(PageHeaderComponent.new(title: "New Feed"))

    assert_equal "New Feed", result.at_css("h1").text
  end

  test "#render should render title icon inside the heading" do
    result = render_inline(PageHeaderComponent.new(title: "New Feed")) do |component|
      component.with_title_icon { "*" }
    end

    assert_equal "* New Feed", result.at_css("h1").text
    assert_includes result.at_css("h1")["class"], "flex"
  end
end
