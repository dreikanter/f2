class ListGroupComponent::StatItemComponent < ViewComponent::Base
  DEFAULT_ITEM_CLASS = "ff-list-group__item p-4"

  def initialize(label:, value:, key: nil)
    @label = label
    @value = value
    @key = key
  end

  def call
    content_tag :li, class: DEFAULT_ITEM_CLASS, data: { key: @key } do
      safe_join(
        [
          content_tag(:span, @label, class: "ff-list-group__title"),
          content_tag(:span, @value, class: "ff-list-group__trailing-text")
        ]
      )
    end
  end
end
