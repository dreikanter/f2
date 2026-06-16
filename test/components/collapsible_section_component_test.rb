require "test_helper"
require "view_component/test_case"

class CollapsibleSectionComponentTest < ViewComponent::TestCase
  test "should render the title and body content" do
    result = render_inline CollapsibleSectionComponent.new(title: "Advanced options") do
      "Hidden details"
    end

    assert_equal "Advanced options", result.css("details summary span").first.text
    assert_includes result.css("details").text, "Hidden details"
  end

  test "should be closed by default" do
    result = render_inline CollapsibleSectionComponent.new(title: "Advanced options")

    assert_nil result.css("details").first["open"]
  end

  test "should start open when open is true" do
    result = render_inline CollapsibleSectionComponent.new(title: "Advanced options", open: true)

    assert_not_nil result.css("details[open]").first
  end

  test "should pass through html options like data attributes" do
    result = render_inline CollapsibleSectionComponent.new(title: "Advanced options", data: { key: "form.advanced-options" })

    details = result.css("details").first

    assert_equal "form.advanced-options", details["data-key"]
    assert_includes details["class"], "group"
  end
end
