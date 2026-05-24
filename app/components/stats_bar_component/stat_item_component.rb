class StatsBarComponent::StatItemComponent < ViewComponent::Base
  DEFAULT_CELL_CLASSES = "flex-1 flex flex-col-reverse items-center justify-center p-4 min-w-0"
  VALUE_CLASSES = "text-2xl font-semibold text-slate-900 whitespace-nowrap"
  LABEL_CLASSES = "text-sm text-slate-600 whitespace-nowrap mt-1"

  def initialize(label:, value:, key: nil)
    @label = label
    @value = value
    @key = key
  end

  def call
    content_tag :div, class: DEFAULT_CELL_CLASSES, data: { key: @key } do
      safe_join([label_element, value_element])
    end
  end

  private

  def value_element
    content_tag(:dd, @value, class: VALUE_CLASSES, data: value_data)
  end

  def label_element
    content_tag(:dt, @label, class: LABEL_CLASSES, data: label_data)
  end

  def value_data
    return if @key.blank?

    { key: "#{@key}.value" }
  end

  def label_data
    return if @key.blank?

    { key: "#{@key}.label" }
  end
end
