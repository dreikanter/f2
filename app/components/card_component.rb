class CardComponent < ViewComponent::Base
  BASE_CLASSES = "w-full rounded-lg border border-border bg-surface shadow-xs"
  PADDED_CLASSES = "p-6"
  # Frameless-on-mobile cards dissolve into the page below the sm breakpoint,
  # so narrow screens keep only the surrounding container padding.
  FRAMELESS_BASE_CLASSES = "w-full sm:rounded-lg sm:border sm:border-border sm:bg-surface sm:shadow-xs"
  FRAMELESS_PADDED_CLASSES = "sm:p-6"
  SECTIONED_CLASSES = "overflow-hidden divide-y divide-border"
  LINKED_CLASSES = "block no-underline hover:bg-surface-muted hover:shadow-md transition duration-75"

  renders_many :sections, CardComponent::SectionComponent

  def initialize(href: nil, frameless_on_mobile: false, **html_options)
    @href = href
    @frameless_on_mobile = frameless_on_mobile
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
      @frameless_on_mobile ? FRAMELESS_BASE_CLASSES : BASE_CLASSES,
      sections.any? ? SECTIONED_CLASSES : padded_classes,
      (@href && LINKED_CLASSES),
      @html_options[:class]
    )
    @html_options.merge(class: classes)
  end

  def padded_classes
    @frameless_on_mobile ? FRAMELESS_PADDED_CLASSES : PADDED_CLASSES
  end
end
