# Abstract base class — subclasses must define DEFAULT_ITEM_CLASS, LABEL_CLASSES, and VALUE_CLASSES.
class StatItemComponent < ViewComponent::Base
  def initialize(label:, value:, key: nil, muted: false, truncate: false)
    @label = label
    @value = value
    @key = key
    @muted = muted
    @truncate = truncate
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
    content_tag(:dd, value_content, class: class_names(self.class::VALUE_CLASSES, @muted ? "text-muted" : "text-heading", "min-w-0" => @truncate), data: value_data)
  end

  # Cropping a long value needs two cooperating pieces: min-w-0 so the flex
  # cell can shrink below its content width, and a block wrapper that crops
  # the overflow with an ellipsis. Bundling them behind one option keeps the
  # contract in one place instead of split across callers.
  def value_content
    return @value unless @truncate

    content_tag(:div, @value, class: "truncate")
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
