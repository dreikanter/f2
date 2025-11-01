require "test_helper"
require "view_component/test_case"

class ListGroupComponentTest < ViewComponent::TestCase
  test "#render should display titles and trailing text" do
    component = ListGroupComponent.new
    component.stat_item(label: "Example item", value: "42")
    result = render_inline(component)

    assert result.css(".ff-list-group").any?
    assert_includes result.css(".ff-list-group__title").map(&:text), "Example item"
    assert_includes result.css(".ff-list-group__trailing-text").map { |node| node.text.strip }, "42"
  end

  test "#render should allow custom body and trailing slots" do
    component = ListGroupComponent.new
    component.with_item StubItemComponent.new(body_text: "Custom body", value: "Trailing slot")
    result = render_inline(component)

    assert_includes result.css(".ff-list-group__body").map { |node| node.text.strip }, "Custom body"
    assert_equal ["Trailing slot"], result.css(".ff-list-group__trailing-text").map { |node| node.text.strip }
  end

  class StubItemComponent < ViewComponent::Base
    def initialize(body_text:, value:)
      @body_text = body_text
      @value = value
      @padding_class = "p-4"
    end

    def call
      content_tag :li, class: class_names("ff-list-group__item", @padding_class) do
        safe_join([
          content_tag(:div, @body_text, class: "ff-list-group__body"),
          content_tag(:span, @value, class: "ff-list-group__trailing-text")
        ])
      end
    end
  end
end
