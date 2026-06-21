class SlotListComponent < ViewComponent::Base
  # Polymorphic slot: items are pre-built components, so the lambda just
  # passes them through to be rendered. Subclasses define the container tag
  # and a DEFAULT_CSS_CLASSES constant.
  renders_many :items, ->(item) { item }

  def initialize(css_class: nil, data: {})
    @css_class = css_class
    @data = data
  end

  def call
    return unless items?

    content_tag container_tag, class: @css_class || self.class::DEFAULT_CSS_CLASSES, data: @data do
      safe_join(items)
    end
  end

  private

  def container_tag
    raise NotImplementedError, "#{self.class} must define #container_tag"
  end
end
