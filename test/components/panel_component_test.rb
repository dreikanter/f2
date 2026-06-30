require "test_helper"
require "view_component/test_case"

class PanelComponentTest < ViewComponent::TestCase
  test "#call should render a div with default styling" do
    result = render_inline(PanelComponent.new) { "Panel body" }

    panel = result.at_css("div")
    assert_not_nil panel
    assert_equal "Panel body", panel.text.strip
    assert_includes panel["class"], "bg-surface-sunken"
    assert_includes panel["class"], "rounded-lg"
    assert_includes panel["class"], "p-6"
    refute_includes panel["class"], "border"
  end

  test "#call should render the info variant with a blue surface" do
    result = render_inline(PanelComponent.new(variant: :info)) { "Heads up" }

    panel = result.at_css("div")
    assert_not_nil panel
    assert_includes panel["class"], "bg-brand-subtle"
    assert_includes panel["class"], "border-brand-subtle"
    refute_includes panel["class"], "bg-surface-sunken"
  end

  test "#call should merge classes and forward html attributes" do
    result = render_inline(
      PanelComponent.new(
        class: "test",
        role: "status",
        data: { controller: "polling" },
        id: "test-panel"
      )
    ) { "<p>Polling...</p>".html_safe }

    panel = result.at_css('[role="status"]')
    assert_not_nil panel
    assert_equal "polling", panel["data-controller"]
    assert_equal "test-panel", panel["id"]
    assert_equal "Polling...", panel.css("p").first.text
    assert_includes panel["class"], "test"
  end
end
