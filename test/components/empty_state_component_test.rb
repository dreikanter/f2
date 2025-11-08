require "test_helper"

class EmptyStateComponentTest < ViewComponent::TestCase
  test "renders empty state with provided content" do
    render_inline EmptyStateComponent.new do
      "Test content"
    end

    assert_selector ".ff-card .ff-card__body.text-center.py-12", text: "Test content"
  end

  test "renders empty state with HTML content" do
    render_inline EmptyStateComponent.new do
      '<h2 class="ff-h2">No items</h2><p>Add some items to get started.</p>'.html_safe
    end

    assert_selector ".ff-card .ff-card__body h2.ff-h2", text: "No items"
    assert_selector ".ff-card .ff-card__body p", text: "Add some items to get started."
  end
end
