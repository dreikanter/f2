class CardComponent < ViewComponent::Base
  BASE_CLASSES = "w-full rounded-lg border border-slate-200 bg-white shadow-xs"
  PADDED_CLASSES = "p-6"
  SECTIONED_CLASSES = "overflow-hidden divide-y divide-slate-200"
  LINKED_CLASSES = "block no-underline hover:bg-slate-50 hover:shadow-md transition duration-75"

  renders_many :sections, CardComponent::SectionComponent

  def initialize(href: nil, **html_options)
    @href = href
    @html_options = html_options
  end

  def call
    if @href
      link_to(@href, **merged_options) { body }
    else
      content_tag(:div, body, merged_options)
    end
  end

  private

  # Sections render as border-to-border regions; a plain card renders its block
  # content in a single padded box.
  def body
    sections.any? ? safe_join(sections) : content
  end

  def merged_options
    classes = helpers.class_names(
      BASE_CLASSES,
      sections.any? ? SECTIONED_CLASSES : PADDED_CLASSES,
      (@href && LINKED_CLASSES),
      @html_options[:class]
    )
    @html_options.merge(class: classes)
  end
end
