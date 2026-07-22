class CardComponent < ViewComponent::Base
  BASE_CLASSES = "w-full rounded-lg border border-border bg-surface shadow-xs"
  PADDED_CLASSES = "p-6"
  SECTIONED_CLASSES = "overflow-hidden divide-y divide-border"

  renders_many :sections, CardComponent::SectionComponent

  def initialize(**html_options)
    @html_options = html_options
  end

  def call
    content_tag(:div, body, merged_options)
  end

  private

  # Sections render as border-to-border regions; a plain card renders its block
  # content in a single padded box.
  def body
    sections.any? ? safe_join(sections) : content
  end

  def merged_options
    classes = helpers.class_names(
      # Resolved through self.class so subclasses restyle by overriding the constants.
      self.class::BASE_CLASSES,
      sections.any? ? SECTIONED_CLASSES : self.class::PADDED_CLASSES,
      @html_options[:class]
    )
    @html_options.merge(class: classes)
  end
end
