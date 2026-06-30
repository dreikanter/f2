require "test_helper"
require "view_component/test_case"

class AlertComponentTest < ViewComponent::TestCase
  test "#call should render an info alert by default" do
    result = render_inline(AlertComponent.new) { "Heads up" }

    alert = result.at_css('[role="alert"]')
    assert_not_nil alert
    assert_equal "Heads up", alert.text.strip
    assert_includes alert["class"], "bg-brand-subtle"
    assert_includes alert["class"], "text-brand-strong"
  end

  test "#call should apply variant classes" do
    %i[info success error warning secondary].each do |variant|
      result = render_inline(AlertComponent.new(variant: variant)) { "msg" }
      classes = result.at_css('[role="alert"]')["class"]
      AlertComponent::VARIANT_CLASSES.fetch(variant).split.each do |expected|
        assert_includes classes, expected, "#{variant} should include #{expected}"
      end
    end
  end

  test "#call should merge caller classes and forward html attributes" do
    result = render_inline(
      AlertComponent.new(variant: :warning, class: "space-y-2", id: "my-alert", data: { key: "test" })
    ) { "body" }

    alert = result.at_css("#my-alert")
    assert_not_nil alert
    assert_equal "alert", alert["role"]
    assert_equal "test", alert["data-key"]
    assert_includes alert["class"], "space-y-2"
    assert_includes alert["class"], "bg-warning-subtle"
  end
end
