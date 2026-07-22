require "test_helper"
require "view_component/test_case"

class LinkedCardComponentTest < ViewComponent::TestCase
  test "#call should render an anchor with hover affordances" do
    result = render_inline(
      LinkedCardComponent.new(href: "/somewhere", target: "_blank", rel: "noopener")
    ) { "Linked card" }

    card = result.at_css("a")
    assert_not_nil card
    assert_equal "/somewhere", card["href"]
    assert_equal "Linked card", card.text.strip
    assert_equal "_blank", card["target"]
    assert_equal "noopener", card["rel"]
    assert_includes card["class"], "bg-surface"
    assert_includes card["class"], "p-6"
    assert_includes card["class"], "hover:shadow-md"
    assert_includes card["class"], "hover:bg-surface-muted"
    assert_includes card["class"], "no-underline"
  end
end
