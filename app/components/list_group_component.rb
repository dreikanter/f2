class ListGroupComponent < ViewComponent::Base
  DEFAULT_CSS_CLASSES = "overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm divide-y divide-slate-200"

  attr_reader :items

  def initialize(css_class: nil, tag: :ul)
    @items = []
    @css_class = css_class
    @tag = tag
  end

  def call
    return if @items.empty?

    content_tag @tag, class: @css_class || DEFAULT_CSS_CLASSES do
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
