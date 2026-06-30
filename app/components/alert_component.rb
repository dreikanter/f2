class AlertComponent < ViewComponent::Base
  VARIANT_CLASSES = {
    info:      "border-brand-subtle bg-brand-subtle text-brand-strong",
    success:   "border-success-subtle bg-success-subtle text-success-strong",
    error:     "border-danger-subtle bg-danger-subtle text-danger-strong",
    warning:   "border-warning-subtle bg-warning-subtle text-warning-strong",
    secondary: "border-brand-subtle bg-surface-sunken text-body"
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
