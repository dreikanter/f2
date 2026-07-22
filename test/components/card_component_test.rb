require "test_helper"
require "view_component/test_case"

class CardComponentTest < ViewComponent::TestCase
  test "#call should render a div with default styling" do
    result = render_inline(CardComponent.new) { "Card body" }

    card = result.at_css("div")
    assert_not_nil card
    assert_equal "Card body", card.text.strip
    assert_includes card["class"], "bg-surface"
    assert_includes card["class"], "rounded-lg"
    assert_includes card["class"], "p-6"
  end

  test "#call should render sections divided border-to-border" do
    result = render_inline(CardComponent.new) do |card|
      card.with_section { "Header" }
      card.with_section { "Footer" }
    end

    card = result.at_css("div")
    assert_includes card["class"], "divide-y"
    assert_includes card["class"], "overflow-hidden"
    refute_includes card["class"], "p-6"

    sections = card.css("> div")
    assert_equal ["Header", "Footer"], sections.map { |section| section.text.strip }
  end

  test "#call should merge classes and forward html attributes" do
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

  test "#call should render an anchor when href is given" do
    result = render_inline(
      CardComponent.new(href: "/somewhere", target: "_blank", rel: "noopener")
    ) { "Linked card" }

    card = result.at_css("a")
    assert_not_nil card
    assert_equal "/somewhere", card["href"]
    assert_equal "_blank", card["target"]
    assert_equal "noopener", card["rel"]
    assert_includes card["class"], "hover:shadow-md"
    assert_includes card["class"], "hover:bg-surface-muted"
    assert_includes card["class"], "no-underline"
  end
end
