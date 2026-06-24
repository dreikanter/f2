require "test_helper"
require "view_component/test_case"

class HeaderMenuComponentTest < ViewComponent::TestCase
  test "#render should style the trigger like the page-header buttons" do
    result = render_inline(HeaderMenuComponent.new(menu_id: "m", items: []))

    button_class = result.at_css("button[data-dropdown-toggle='m']")["class"]
    assert_includes button_class, "border"
    assert_includes button_class, "p-3"
    assert_not_includes button_class, "size-7"
  end

  test "#render should inherit the dropdown menu and its items" do
    result = render_inline(HeaderMenuComponent.new(menu_id: "m", items: [
      { label: "Edit", href: "/feeds/1" }
    ]))

    assert_not_nil result.at_css("#m[role='menu']")
    assert_equal "Edit", result.at_css("a[role='menuitem']").text.strip
  end
end
