require "test_helper"
require "view_component/test_case"

class EmptyStateComponentTest < ViewComponent::TestCase
  test "should render empty state with provided content" do
    result = render_inline EmptyStateComponent.new do
      "Test content"
    end

    body = result.css('[data-key="empty-state.body"]').first

    assert_not_nil body
    assert_includes body.text, "Test content"
  end

  test "#render should render text argument as a paragraph" do
    result = render_inline EmptyStateComponent.new("Nothing here yet")

    paragraph = result.css("p.text-slate-500").first

    assert_not_nil paragraph
    assert_equal "Nothing here yet", paragraph.text.strip
  end

  test "#render should prefer block content over text argument" do
    result = render_inline EmptyStateComponent.new("Ignored text") do
      "Block content"
    end

    body = result.css('[data-key="empty-state.body"]').first

    assert_includes body.text, "Block content"
    assert_not_includes body.text, "Ignored text"
  end
end
