require "test_helper"
require "view_component/test_case"

class PageHeaderComponentTest < ViewComponent::TestCase
  test "#render should render title without surrounding whitespace" do
    result = render_inline(PageHeaderComponent.new(title: "New Feed"))

    assert_equal "New Feed", result.at_css("h1").text
  end

  test "#render should place the title suffix after the heading" do
    result = render_inline(PageHeaderComponent.new(title: "My Feed")) do |component|
      component.with_title_suffix { "Refreshing feed" }
    end

    assert_equal "My Feed", result.at_css("h1").text
    assert_includes result.at_css("h1").parent.text, "Refreshing feed"
  end

  test "#render should render markup in a context paragraph and escape plain text" do
    result = render_inline(PageHeaderComponent.new(title: "New Feed")) do |component|
      component.with_context_paragraph("Needs <code>Key</code>".html_safe)
      component.with_context_paragraph("Plain <b>text</b>")
    end

    assert_equal "Key", result.at_css("p code").text
    assert_equal "Plain <b>text</b>", result.css("p").last.text
  end
end
