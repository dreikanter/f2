class ListGroupComponent < ViewComponent::Base
  PADDING_CLASSES = {
    sm: "px-3 py-3",
    md: "p-4",
    lg: "px-5 py-5"
  }.freeze

  DEFAULT_PADDING = :md

  attr_reader :padding

  def initialize(list_classes: nil, padding: DEFAULT_PADDING, divided: true)
    @list_classes = list_classes
    @padding = padding
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

  def item_padding_class
    PADDING_CLASSES.fetch(padding.to_sym, PADDING_CLASSES[DEFAULT_PADDING])
  end

  def item_classes
    class_names("ff-list-group__item", item_padding_class)
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
    with_item StatItemComponent.new(label: label, value: value, padding_class: item_padding_class)
  end
end
