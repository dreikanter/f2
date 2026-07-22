# A card that is itself a link: renders as an anchor and layers hover
# affordances on top of the regular card frame.
class LinkedCardComponent < CardComponent
  BASE_CLASSES = "#{CardComponent::BASE_CLASSES} block no-underline hover:bg-surface-muted hover:shadow-md transition duration-75"

  def initialize(href:, **html_options)
    @href = href
    super(**html_options)
  end

  def call
    link_to(@href, **merged_options) { body }
  end
end
