require "test_helper"
require "view_component/test_case"

class ListComponent::ItemComponentTest < ViewComponent::TestCase
  test "#call should render title as a link when title_url is given" do
    component = ListComponent::ItemComponent.new(title: "My Item", title_url: "/items/1")
    result = render_inline(component)
    link = result.css("a").first

    assert_not_nil link
    assert_equal "My Item", link.text.strip
    assert_includes link["href"], "/items/1"
  end

  test "#call should render title as plain text when title_url is nil" do
    component = ListComponent::ItemComponent.new(title: "Plain Title", title_url: nil)
    result = render_inline(component)

    assert_empty result.css("a")
    assert_includes result.text, "Plain Title"
  end

  test "#call should render metadata segments separated by bullets" do
    component = ListComponent::ItemComponent.new(
      title: "Item",
      title_url: "#",
      metadata_segments: ["First", "Second", "Third"]
    )
    result = render_inline(component)

    assert_includes result.text, "First"
    assert_includes result.text, "Second"
    assert_includes result.text, "Third"
    assert_equal 2, result.css("[aria-hidden='true']").size
  end

  test "#call should render actions when provided" do
    component = ListComponent::ItemComponent.new(
      title: "Item",
      title_url: "#",
      actions: "<button>Click me</button>".html_safe
    )
    result = render_inline(component)

    assert_includes result.text, "Click me"
  end

  test "#call should render note when provided" do
    component = ListComponent::ItemComponent.new(
      title: "Item",
      title_url: "#",
      note: "<p>A note</p>".html_safe
    )
    result = render_inline(component)

    assert_includes result.text, "A note"
  end

  test "#call should set data-key when key is provided" do
    component = ListComponent::ItemComponent.new(title: "Item", title_url: "#", key: "test.key")
    result = render_inline(component)

    assert_not_nil result.css("[data-key='test.key']").first
  end

  test "#call should omit data-key when key is nil" do
    component = ListComponent::ItemComponent.new(title: "Item", title_url: "#")
    result = render_inline(component)

    assert_nil result.css("li").first["data-key"]
  end
end
