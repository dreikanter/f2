class PanelComponent < ViewComponent::Base
  # A borderless container on the same light gray surface as the navbar, used to
  # set a block of related content apart without the weight of a bordered card.
  BASE_CLASSES = "w-full rounded-lg bg-slate-100 p-6"

  def initialize(**html_options)
    @html_options = html_options
  end

  def call
    content_tag(:div, content, merged_options)
  end

  private

  def merged_options
    classes = helpers.class_names(BASE_CLASSES, @html_options[:class])
    @html_options.merge(class: classes)
  end
end
