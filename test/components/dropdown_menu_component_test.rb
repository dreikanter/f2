require "test_helper"
require "view_component/test_case"

class DropdownMenuComponentTest < ViewComponent::TestCase
  test "#render should wire the button to its menu" do
    result = render_inline(DropdownMenuComponent.new(menu_id: "feed-menu-1", items: []))

    button = result.at_css("button[data-dropdown-toggle='feed-menu-1']")
    assert_not_nil button
    assert_not_nil result.at_css("#feed-menu-1[role='menu']")
  end

  test "#render should apply the given width to the popover" do
    result = render_inline(DropdownMenuComponent.new(menu_id: "m", items: [], width: "w-40"))

    assert_includes result.at_css("#m")["class"], "w-40"
  end

  test "#render should render plain items as links carrying their data" do
    result = render_inline(DropdownMenuComponent.new(menu_id: "m", items: [
      { label: "Details", href: "/feeds/1", data: { key: "feed.1.details" } }
    ]))

    link = result.at_css("a[role='menuitem'][data-key='feed.1.details']")
    assert_not_nil link
    assert_equal "Details", link.text.strip
    assert_equal "/feeds/1", link["href"]
  end

  test "#render should open external links in a new tab" do
    result = render_inline(DropdownMenuComponent.new(menu_id: "m", items: [
      { label: "Source", href: "https://example.com", target: "_blank", rel: "noopener" }
    ]))

    link = result.at_css("a[role='menuitem']")
    assert_equal "_blank", link["target"]
    assert_equal "noopener", link["rel"]
  end

  test "#render should render items with a method as button_to forms" do
    result = render_inline(DropdownMenuComponent.new(menu_id: "m", items: [
      { label: "Disable", href: "/feeds/1/status", method: :patch, params: { status: "disabled" },
        data: { key: "feed.1.disable", turbo_confirm: "Sure?" } }
    ]))

    form = result.at_css("form[action='/feeds/1/status']")
    assert_not_nil form
    assert_not_nil form.at_css("input[name='_method'][value='patch']", "input[type='hidden']")
    button = result.at_css("button[role='menuitem'][data-key='feed.1.disable']")
    assert_not_nil button
    assert_equal "Disable", button.text.strip
    assert_equal "Sure?", button["data-turbo-confirm"]
  end

  test "#render should drop nil items" do
    result = render_inline(DropdownMenuComponent.new(menu_id: "m", items: [
      { label: "Details", href: "#" },
      nil
    ]))

    assert_equal 1, result.css("li").size
  end
end
