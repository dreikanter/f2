class CardComponent < ViewComponent::Base
  BASE_CLASSES = "w-full rounded-none border-0 bg-white p-0 " \
                 "sm:rounded-lg sm:border sm:border-slate-200 sm:p-6 sm:shadow-xs"
  LINKED_CLASSES = "block no-underline hover:shadow-lg transition-shadow"

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
