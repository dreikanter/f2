class ListGroupComponent < ViewComponent::Base
  attr_reader :items

  def initialize(list_classes: nil, divided: true)
    @list_classes = list_classes
    @divided = divided
    @items = []
  end

  def call
    return if @items.empty?

    content_tag :ul, class: list_classes do
      safe_join(@items.map { |item| item.render_in(view_context) })
    end
  end

  def list_classes
    class_names(
      "ff-list-group",
      { "divide-y divide-slate-200": @divided },
      @list_classes
    )
  end

  def with_item(component)
    @items << component
    component
  end
  alias_method :add_item, :with_item

  def items
    @items
  end

  def items?
    @items.any?
  end

  def stat_item(label:, value:)
    with_item StatItemComponent.new(label: label, value: value)
  end
end
