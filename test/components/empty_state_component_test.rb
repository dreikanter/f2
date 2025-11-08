require "test_helper"

class EmptyStateComponentTest < ViewComponent::TestCase
  test "renders empty state with provided content" do
    render_inline EmptyStateComponent.new do
      "Test content"
    end

    assert_selector '[data-key="empty-state.body"]', text: "Test content"
  end

  test "renders empty state with HTML content" do
    render_inline EmptyStateComponent.new do
      '<h2 class="ff-h2">No items</h2><p>Add some items to get started.</p>'.html_safe
    end

    assert_selector '[data-key="empty-state.body"]', text: "No items"
    assert_selector '[data-key="empty-state.body"]', text: "Add some items to get started."
  end
end
