class AlertComponent < ViewComponent::Base
  VARIANT_CLASSES = {
    info:      "border-sky-100 bg-sky-100 text-sky-800",
    success:   "border-emerald-200 bg-emerald-100 text-emerald-800",
    error:     "border-red-200 bg-red-100 text-red-800",
    warning:   "border-amber-200 bg-amber-100 text-amber-800",
    secondary: "border-sky-100 bg-surface-sunken text-body"
  }.freeze

  BASE_CLASSES = "rounded-lg border px-4 py-3 flex items-start gap-2"

  def initialize(variant: :info, icon: nil, **html_options)
    @variant = variant
    @icon = icon
    @html_options = html_options
  end

  def call
    icon_html = @icon.present? ? helpers.icon(@icon, css_class: "size-5 mt-0.5") : "".html_safe
    body_html = content_tag(:div, content, class: "space-y-1")
    content_tag(:div, icon_html + body_html, merged_options)
  end

  private

  def merged_options
    classes = helpers.class_names(BASE_CLASSES, VARIANT_CLASSES.fetch(@variant), @html_options[:class])
    { role: "alert" }.merge(@html_options).merge(class: classes)
  end
end
