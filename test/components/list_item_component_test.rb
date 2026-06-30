require "test_helper"
require "view_component/test_case"

class ListItemComponentTest < ViewComponent::TestCase
  test "#call should render an li carrying id, data and css_class" do
    result = render_inline(ListItemComponent.new(id: "row-1", css_class: "bg-warning-subtle", data: { key: "list.row" })) do |item|
      item.with_primary { "Primary".html_safe }
    end

    li = result.at_css("li#row-1")
    assert_not_nil li
    assert_equal "list.row", li["data-key"]
    assert_includes li["class"], "bg-warning-subtle"
    assert_includes li["class"], "px-5 py-3"
  end

  test "#call should round the first and last row corners" do
    result = render_inline(ListItemComponent.new(id: "row-1")) do |item|
      item.with_primary { "Primary".html_safe }
    end

    li = result.at_css("li#row-1")
    assert_includes li["class"], "first:rounded-t-lg"
    assert_includes li["class"], "last:rounded-b-lg"
  end

  test "#call should render every slot when provided" do
    result = render_inline(ListItemComponent.new) do |item|
      item.with_icon { "<svg></svg>".html_safe }
      item.with_primary { "<span>Title</span>".html_safe }
      item.with_secondary { "<span>Meta</span>".html_safe }
      item.with_trailing { "<button>Menu</button>".html_safe }
    end

    assert_not_nil result.at_css("li svg")
    assert_includes result.text, "Title"
    assert_includes result.text, "Meta"
    assert_not_nil result.at_css("li button")
  end

  test "#call should hang the second line under the primary text when an icon is present" do
    result = render_inline(ListItemComponent.new) do |item|
      item.with_icon { "<svg></svg>".html_safe }
      item.with_primary { "Title".html_safe }
      item.with_secondary { "Meta".html_safe }
    end

    assert_includes secondary_classes(result), "pl-7"
  end

  test "#call should not indent the second line without an icon" do
    result = render_inline(ListItemComponent.new) do |item|
      item.with_primary { "Title".html_safe }
      item.with_secondary { "Meta".html_safe }
    end

    assert_not_includes secondary_classes(result), "pl-7"
  end

  test "#call should omit optional slots that are not provided" do
    result = render_inline(ListItemComponent.new) do |item|
      item.with_primary { "Only primary".html_safe }
    end

    assert_includes result.text, "Only primary"
    assert_nil result.at_css("li svg")
    assert_nil result.at_css("li button")
  end

  test "#call should integrate with ListComponent as a list item" do
    result = render_inline(ListComponent.new) do |list|
      item = ListItemComponent.new(id: "row-9")
      item.with_primary { "In a list".html_safe }
      list.with_item(item)
    end

    assert_not_nil result.at_css("ul > li#row-9")
    assert_includes result.text, "In a list"
  end

  private

  # The component wraps the secondary slot in its own div; the slot content here
  # is plain text, so the wrapper is the element right above the text node.
  def secondary_classes(result)
    result.css("li div div").map { |node| node["class"].to_s }.join(" ")
  end
end
