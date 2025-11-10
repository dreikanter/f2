class StatsBarComponent < ViewComponent::Base
  DEFAULT_BAR_CLASSES = "hidden md:flex md:divide-x md:divide-slate-200"

  attr_reader :items

  def initialize(css_class: nil)
    @items = []
    @css_class = css_class
  end

  def call
    return if @items.empty?

    content_tag :div, class: @css_class || DEFAULT_BAR_CLASSES do
      safe_join(@items.map { |item| item.render_in(view_context) })
    end
  end

  def with_item(component)
    @items << component
    component
  end

  def with_items(components)
    components.each { |component| @items << component }
    self
  end

  def items?
    items.any?
  end
end
