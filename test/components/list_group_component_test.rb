require "test_helper"
require "view_component/test_case"

class ListGroupComponentTest < ViewComponent::TestCase
  test "#render should display titles and trailing text" do
    component = ListGroupComponent.new
    component.with_item(ListGroupComponent::StatItemComponent.new(label: "Example item", value: "42", key: "example"))
    result = render_inline(component)

    assert result.css(".ff-list-group").any?
    item = result.css('[data-key="example"]').first
    assert_not_nil item
    assert_equal "Example item", result.css('[data-key="example.label"]').first.text
    assert_equal "42", result.css('[data-key="example.value"]').first.text
  end

  test "#render should allow custom body and trailing slots" do
    component = ListGroupComponent.new
    component.with_item StubItemComponent.new(body_text: "Custom body", value: "Trailing slot", key: "custom")
    result = render_inline(component)

    item = result.css('[data-key="custom"]').first
    assert_not_nil item
    assert_equal "Custom body", result.css('[data-key="custom.label"]').first.text.strip
    assert_equal "Trailing slot", result.css('[data-key="custom.value"]').first.text.strip
  end

  class StubItemComponent < ViewComponent::Base
    def initialize(body_text:, value:, key:)
      @body_text = body_text
      @value = value
      @padding_class = "p-4"
      @key = key
    end

    def call
      content_tag :li, class: class_names("ff-list-group__item", @padding_class), data: { key: @key } do
        safe_join([
          content_tag(:span, @body_text, class: "ff-list-group__title", data: { key: "#{@key}.label" }),
          content_tag(:span, @value, class: "ff-list-group__trailing-text", data: { key: "#{@key}.value" })
        ])
      end
    end
  end
end
