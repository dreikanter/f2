require "test_helper"
require "view_component/test_case"

class GroupsRefreshControlComponentTest < ViewComponent::TestCase
  test "#render should render the trigger with the caller's wiring when idle" do
    result = render_inline(GroupsRefreshControlComponent.new(key_prefix: "feed", data: {
      controller: "loading-button",
      action: "click->groups#refreshGroups"
    }))

    button = result.at_css("button")
    assert_equal "click->groups#refreshGroups", button["data-action"]
    assert_equal "feed.refresh-groups", button["data-key"]
    assert_nil button["disabled"]
    assert_nil button["hidden"]
    assert_empty result.css("[data-polling-target]")
  end

  test "#render should render nothing when no refresh is possible" do
    result = render_inline(GroupsRefreshControlComponent.new(key_prefix: "feed", available: false))

    assert_empty result.css("button")
  end

  test "#render should show a disabled spinning button while refreshing" do
    result = render_inline(GroupsRefreshControlComponent.new(key_prefix: "access_token", refreshing: true,
                                                            type: "submit"))

    spinning, trigger = result.css("button").to_a
    assert_equal "content", spinning["data-polling-target"]
    assert_equal "access_token.groups-refreshing", spinning["data-key"]
    assert_equal "disabled", spinning["disabled"]
    assert_not_nil spinning.at_css("svg.animate-spin")

    # same classes as the trigger, so swapping states can't move the layout
    assert_equal trigger["class"], spinning["class"]
  end

  test "#render should keep the trigger and a note hidden until the refresh times out" do
    result = render_inline(GroupsRefreshControlComponent.new(key_prefix: "access_token", refreshing: true,
                                                            type: "submit"))

    trigger = result.css("button").last
    assert_equal "timeoutMessage", trigger["data-polling-target"]
    assert_equal "submit", trigger["type"]
    assert_equal "hidden", trigger["hidden"]

    note = result.at_css('[data-key="access_token.groups-refresh-timeout"]')
    assert_equal "timeoutMessage", note["data-polling-target"]
    assert_equal "hidden", note["hidden"]
    assert_match(/taking longer than expected/, note.text)
  end
end
