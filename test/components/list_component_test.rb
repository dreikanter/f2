require "test_helper"
require "view_component/test_case"

class ListComponentTest < ViewComponent::TestCase
  test "#render should render a ul container" do
    component = ListComponent.new
    component.with_item StubItemComponent.new(body_text: "Custom body", value: "Trailing slot", key: "stats.custom")
    result = render_inline(component)

    assert_not_nil result.at_css("ul")
    item = result.css('[data-key="stats.custom"]').first
    assert_not_nil item
    assert_equal "Custom body", result.css('[data-key="stats.custom.label"]').first.text.strip
    assert_equal "Trailing slot", result.css('[data-key="stats.custom.value"]').first.text.strip
  end

  test "#render should support block-based slot population" do
    result = render_inline(ListComponent.new) do |list|
      list.with_item StubItemComponent.new(body_text: "Block item", value: "Block value", key: "stats.block")
    end

    assert_not_nil result.at_css("ul")
    assert_equal "Block item", result.css('[data-key="stats.block.label"]').first.text.strip
    assert_equal "Block value", result.css('[data-key="stats.block.value"]').first.text.strip
  end

  class StubItemComponent < ViewComponent::Base
    def initialize(body_text:, value:, key:)
      @body_text = body_text
      @value = value
      @key = key
    end

    def call
      content_tag :li, data: { key: @key } do
        safe_join([
          content_tag(:span, @body_text, data: { key: "#{@key}.label" }),
          content_tag(:span, @value, data: { key: "#{@key}.value" })
        ])
      end
    end
  end
end
