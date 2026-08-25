require "test_helper"
require "view_component/test_case"

class StatsPanelComponentTest < ViewComponent::TestCase
  class SampleStatsComponent < StatsPanelComponent
    private

    def layout_items
      [
        { key: "plain", label: "Plain figure", label_short: "Plain", value: "1" },
        { key: "dimmed", label: "Dimmed figure", label_short: "Dimmed", value: "0", muted: true },
        { key: "same", label: "Same", label_short: "Same", value: "2" }
      ]
    end
  end

  class NamespacedStatsComponent < SampleStatsComponent
    private

    def key_prefix
      "custom_stats"
    end
  end

  test "#render should render every item in both layouts" do
    result = render_inline(SampleStatsComponent.new)

    assert_equal "Plain figure", result.css('.md\\:hidden [data-key="stats.plain.label"]').first.text
    assert_equal "Plain", result.css('.hidden.md\\:flex [data-key="stats.plain.label"]').first.text
    assert_equal "1", result.css('.hidden.md\\:flex [data-key="stats.plain.value"]').first.text
  end

  test "#render should mute only the items that ask for it" do
    result = render_inline(SampleStatsComponent.new)

    assert_includes result.css('.md\\:hidden [data-key="stats.dimmed.value"]').first["class"], "text-muted"
    assert_not_includes result.css('.md\\:hidden [data-key="stats.plain.value"]').first["class"], "text-muted"
  end

  test "#render should namespace data keys with the subclass key_prefix" do
    result = render_inline(NamespacedStatsComponent.new)

    assert_not_nil result.css('[data-key="custom_stats.plain.label"]').first
    assert_nil result.css('[data-key="stats.plain.label"]').first
  end

  test "#render should show the full label as a tooltip on the bar only" do
    result = render_inline(SampleStatsComponent.new)

    assert_equal "Plain figure", result.css('.hidden.md\\:flex [data-key="stats.plain"]').first["data-tippy-content"]
    assert_nil result.css('.md\\:hidden [data-key="stats.plain"]').first["data-tippy-content"]
  end

  test "#render should skip the tooltip when both labels read the same" do
    result = render_inline(SampleStatsComponent.new)

    assert_nil result.css('.hidden.md\\:flex [data-key="stats.same"]').first["data-tippy-content"]
  end

  test "#render should hook the bar up to the tooltips controller" do
    result = render_inline(SampleStatsComponent.new)

    assert_equal "tooltips", result.css(".hidden.md\\:flex").first["data-controller"]
  end

  test "#layout_items should raise NotImplementedError when not overridden" do
    error = assert_raises(NotImplementedError) { render_inline(StatsPanelComponent.new) }
    assert_includes error.message, "must implement #layout_items"
  end
end
