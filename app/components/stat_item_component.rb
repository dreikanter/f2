# Abstract base class — subclasses must define DEFAULT_ITEM_CLASS, LABEL_CLASSES, and VALUE_CLASSES.
class StatItemComponent < ViewComponent::Base
  def initialize(label:, value:, key: nil, muted: false)
    @label = label
    @value = value
    @key = key
    @muted = muted
  end

  def call
    content_tag :div, class: self.class::DEFAULT_ITEM_CLASS, data: { key: @key } do
      safe_join([label_element, value_element])
    end
  end

  private

  def label_element
    content_tag(:dt, @label, class: self.class::LABEL_CLASSES, data: label_data)
  end

  def value_element
    content_tag(:dd, @value, class: class_names(self.class::VALUE_CLASSES, @muted ? "text-muted" : "text-heading"), data: value_data)
  end

  def label_data
    return if @key.blank?

    { key: "#{@key}.label" }
  end

  def value_data
    return if @key.blank?

    { key: "#{@key}.value" }
  end
end
