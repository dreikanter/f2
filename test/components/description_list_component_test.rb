require "test_helper"
require "view_component/test_case"

class DescriptionListComponentTest < ViewComponent::TestCase
  test "#render should render a dl container with stat items" do
    component = DescriptionListComponent.new
    component.with_item(ListComponent::StatItemComponent.new(label: "Example item", value: "42", key: "stats.example"))
    result = render_inline(component)

    assert_not_nil result.at_css("dl")
    assert_not_nil result.css('[data-key="stats.example"]').first
    assert_equal "Example item", result.css('[data-key="stats.example.label"]').first.text
    assert_equal "42", result.css('[data-key="stats.example.value"]').first.text
  end
end
