class ListGroupComponent::StatItemComponent < ViewComponent::Base
  DEFAULT_ITEM_CLASS = "flex items-baseline justify-between gap-4 p-4"
  LABEL_CLASSES = "text-base text-slate-900 whitespace-nowrap"
  VALUE_CLASSES = "text-base text-slate-900"

  def initialize(label:, value:, key: nil)
    @label = label
    @value = value
    @key = key
  end

  def call
    content_tag :div, class: DEFAULT_ITEM_CLASS, data: { key: @key } do
      safe_join([label_dt, value_dd])
    end
  end

  private

  def label_dt
    content_tag(:dt, @label, class: LABEL_CLASSES, data: label_data)
  end

  def value_dd
    content_tag(:dd, @value, class: VALUE_CLASSES, data: value_data)
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
