class ListGroupComponent < ViewComponent::Base
  DEFAULT_LIST_CLASSES = "overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm divide-y divide-slate-200"

  attr_reader :items

  def initialize
    @items = []
  end

  def call
    return if @items.empty?

    content_tag :ul, class: DEFAULT_LIST_CLASSES do
      safe_join(@items.map { |item| item.render_in(view_context) })
    end
  end

  def with_item(component)
    @items << component
    component
  end
  alias_method :add_item, :with_item

  def items?
    items.any?
  end

end
