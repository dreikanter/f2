require "test_helper"
require "view_component/test_case"

class CardComponent::SectionComponentTest < ViewComponent::TestCase
  test "#call should render a padded div with content" do
    result = render_inline(CardComponent::SectionComponent.new) { "Section body" }

    section = result.at_css("div")
    assert_not_nil section
    assert_equal "Section body", section.text.strip
    assert_includes section["class"], "p-6"
  end

  test "#call should merge classes and forward html attributes" do
    result = render_inline(
      CardComponent::SectionComponent.new(class: "extra", data: { key: "stats" })
    ) { "Body" }

    section = result.at_css("div")
    assert_includes section["class"], "extra"
    assert_includes section["class"], "p-6"
    assert_equal "stats", section["data-key"]
  end
end
