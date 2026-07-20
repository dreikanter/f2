require "test_helper"
require "view_component/test_case"

class BetaBadgeComponentTest < ViewComponent::TestCase
  test "#call should render Beta with info badge styling" do
    result = render_inline(BetaBadgeComponent.new)

    badge = result.at_css("span")
    assert_equal "Beta", badge.text
    assert_includes badge["class"], "bg-brand-subtle"
    assert_includes badge["class"], "text-brand-strong"
  end

  test "#call should set data-key when key is given" do
    result = render_inline(BetaBadgeComponent.new(key: "entry.ai-beta-badge"))

    assert_not_nil result.at_css("[data-key='entry.ai-beta-badge']")
  end

  test "#call should omit data-key when key is missing" do
    result = render_inline(BetaBadgeComponent.new)

    assert_nil result.at_css("span")["data-key"]
  end
end
