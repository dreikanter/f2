# Base for the panels that render a row of figures two ways: a stacked
# description list on narrow screens, a horizontal bar on wider ones.
#
# Subclasses supply #layout_items — one hash per figure with :key, :label,
# :label_short, :value, and an optional :muted — and override #key_prefix when
# their data-key hooks live under a different namespace. The bar shows
# :label_short and reveals :label on hover. A figure with nothing behind it yet
# is left blank.
class StatsPanelComponent < ViewComponent::Base
  def call
    tag.div { safe_join([mobile_layout, desktop_layout]) }
  end

  private

  def layout_items
    raise NotImplementedError, "Subclasses must implement #layout_items"
  end

  def key_prefix
    "stats"
  end

  def mobile_layout
    render(DescriptionListComponent.new(css_class: class_names("md:hidden", DescriptionListComponent::DEFAULT_CSS_CLASSES))) do |list|
      layout_items.each { |item| list.with_item(mobile_stat_cell(item)) }
    end
  end

  def desktop_layout
    render(StatsBarComponent.new(css_class: class_names("hidden", StatsBarComponent::DEFAULT_CSS_CLASSES))) do |bar|
      layout_items.each { |item| bar.with_item(desktop_stat_cell(item)) }
    end
  end

  def mobile_stat_cell(item)
    StatListItemComponent.new(
      label: item[:label],
      value: item[:value],
      key: item_key(item),
      muted: item.fetch(:muted, false)
    )
  end

  def desktop_stat_cell(item)
    StatBarItemComponent.new(
      label: item[:label_short],
      value: item[:value],
      key: item_key(item),
      muted: item.fetch(:muted, false),
      tooltip: desktop_tooltip(item)
    )
  end

  # The bar only has room for the short label, so the tooltip spells it out.
  def desktop_tooltip(item)
    item[:label] unless item[:label] == item[:label_short]
  end

  def item_key(item)
    "#{key_prefix}.#{item[:key]}"
  end
end
