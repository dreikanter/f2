require "test_helper"
require "view_component/test_case"

class ModalCardComponentTest < ViewComponent::TestCase
  test "#call should scope the card frame to sm+" do
    result = render_inline(ModalCardComponent.new) { "Card body" }

    card = result.at_css("div")
    assert_equal "Card body", card.text.strip

    classes = card["class"].split
    assert_includes classes, "sm:border"
    assert_includes classes, "sm:rounded-lg"
    assert_includes classes, "sm:p-6"
    refute_includes classes, "border"
    refute_includes classes, "rounded-lg"
    refute_includes classes, "p-6"
  end
end
