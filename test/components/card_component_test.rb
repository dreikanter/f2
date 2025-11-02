require "test_helper"
require "view_component/test_case"

class CardComponentTest < ViewComponent::TestCase
  test "renders content with default styling" do
    result = render_inline(CardComponent.new) { "Card body" }

    card = result.css("div.rounded-xl").first
    assert_not_nil card
    assert_equal "Card body", card.text.strip
  end

  test "merges classes and forwards html attributes" do
    result = render_inline(
      CardComponent.new(
        class: "test",
        role: "status",
        data: { controller: "polling" },
        id: "test-card"
      )
    ) { "<p>Polling...</p>".html_safe }

    card = result.at_css('[role="status"]')
    assert_not_nil card
    assert_equal "polling", card["data-controller"]
    assert_equal "test-card", card["id"]
    assert_equal "Polling...", card.css("p").first.text
    assert_includes card["class"], "test"
  end
end
