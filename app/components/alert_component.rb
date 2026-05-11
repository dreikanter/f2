class AlertComponent < ViewComponent::Base
  VARIANT_CLASSES = {
    info:      "border-sky-100 bg-sky-100 text-sky-800",
    success:   "border-emerald-200 bg-emerald-100 text-emerald-800",
    error:     "border-red-200 bg-red-100 text-red-800",
    warning:   "border-amber-200 bg-amber-100 text-amber-800",
    secondary: "border-sky-100 bg-slate-100 text-slate-600"
  }.freeze

  BASE_CLASSES = "rounded-lg border px-4 py-3"

  def initialize(variant: :info, **html_options)
    @variant = variant
    @html_options = html_options
  end

  def call
    options = { role: "alert" }.merge(@html_options)
    options[:class] = helpers.class_names(BASE_CLASSES, VARIANT_CLASSES.fetch(@variant), @html_options[:class])
    content_tag :div, content, **options
  end
end
