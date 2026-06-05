require "test_helper"
require "view_component/test_case"

class RefreshButtonComponentTest < ViewComponent::TestCase
  test "#render should render a button wired as the loading-button target" do
    result = render_inline(RefreshButtonComponent.new(title: "Refresh now"))

    button = result.at_css("button")
    assert_equal "button", button["type"]
    assert_equal "Refresh now", button["title"]
    assert_equal "button", button["data-loading-button-target"]
  end

  test "#render should show a default icon and a hidden spinner" do
    result = render_inline(RefreshButtonComponent.new)

    default_icon = result.at_css('[data-loading-button-target="default"]')
    loading_icon = result.at_css('[data-loading-button-target="loading"]')

    assert_not_nil default_icon.at_css("svg")
    assert_not_nil loading_icon.at_css("svg.animate-spin")
    assert_includes loading_icon["class"], "hidden"
  end

  test "#render should merge arbitrary attributes onto the button" do
    result = render_inline(RefreshButtonComponent.new(type: "submit", class: "extra", data: {
      controller: "refresh-trigger loading-button",
      action: "click->refresh-trigger#trigger",
      key: "events.refresh"
    }))

    button = result.at_css("button")
    assert_equal "submit", button["type"]
    assert_includes button["class"], "extra"
    assert_includes button["class"], "rounded-md"
    assert_equal "refresh-trigger loading-button", button["data-controller"]
    assert_equal "click->refresh-trigger#trigger", button["data-action"]
    assert_equal "events.refresh", button["data-key"]
    # caller data is merged alongside the built-in loading-button target
    assert_equal "button", button["data-loading-button-target"]
  end
end
