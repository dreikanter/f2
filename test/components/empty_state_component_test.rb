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

  test "should render empty state with HTML content" do
    result = render_inline EmptyStateComponent.new do
      '<h2 class="ff-h2">No items</h2><p>Add some items to get started.</p>'.html_safe
    end

    body = result.css('[data-key="empty-state.body"]').first
    assert_not_nil body
    assert_includes body.text, "No items"
    assert_includes body.text, "Add some items to get started."
  end
end
