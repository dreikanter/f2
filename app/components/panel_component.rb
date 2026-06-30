class PanelComponent < ViewComponent::Base
  BASE_CLASSES = "w-full rounded-lg p-6"

  VARIANT_CLASSES = {
    default: "bg-surface-sunken",
    info: "border border-sky-200 bg-sky-50"
  }.freeze

  def initialize(variant: :default, **html_options)
    @variant = variant
    @html_options = html_options
  end

  def call
    content_tag(:div, content, merged_options)
  end

  private

  def merged_options
    classes = helpers.class_names(BASE_CLASSES, VARIANT_CLASSES.fetch(@variant), @html_options[:class])
    @html_options.merge(class: classes)
  end
end
