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
end
