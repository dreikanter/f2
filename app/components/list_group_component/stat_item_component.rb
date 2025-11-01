class ListGroupComponent::StatItemComponent < ViewComponent::Base
  def initialize(label:, value:, padding_class:)
    @label = label
    @value = value
    @padding_class = padding_class
  end

  def call
    content_tag :li, class: class_names("ff-list-group__item", @padding_class) do
      safe_join(
        [
          content_tag(:span, @label, class: "ff-list-group__title"),
          content_tag(:span, @value, class: "ff-list-group__trailing-text")
        ]
      )
    end
  end
end
