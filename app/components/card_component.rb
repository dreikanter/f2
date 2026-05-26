class CardComponent < ViewComponent::Base
  BASE_CLASSES = "w-full rounded-lg border border-slate-200 bg-white p-6 shadow-xs"
  LINKED_CLASSES = "block no-underline hover:bg-slate-50 hover:shadow-md transition duration-75"

  def initialize(href: nil, **html_options)
    @href = href
    @html_options = html_options
  end

  def call
    if @href
      link_to(@href, **merged_options) { content }
    else
      content_tag(:div, content, merged_options)
    end
  end

  private

  def merged_options
    classes = helpers.class_names(BASE_CLASSES, (@href && LINKED_CLASSES), @html_options[:class])
    @html_options.merge(class: classes)
  end
end
