class PanelComponent < ViewComponent::Base
  # A borderless container on the same light gray surface as the navbar, used to
  # set a block of related content apart without the weight of a bordered card.
  # The :info variant swaps in a blue surface to flag a section that needs the
  # user's attention while keeping the panel's shape and spacing.
  BASE_CLASSES = "w-full rounded-lg p-6"

  VARIANT_CLASSES = {
    default: "bg-slate-100",
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
