class CardComponent::SectionComponent < ViewComponent::Base
  DEFAULT_CLASSES = "p-6"

  def initialize(**html_options)
    @html_options = html_options
  end

  def call
    content_tag(:div, content, merged_options)
  end

  private

  # An explicit class replaces the default padding rather than merging with it,
  # so callers stay in full control of a section's spacing.
  def merged_options
    @html_options.merge(class: @html_options[:class].presence || DEFAULT_CLASSES)
  end
end
