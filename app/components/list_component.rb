class ListComponent < ViewComponent::Base
  DEFAULT_CSS_CLASSES = "overflow-hidden rounded-lg border border-slate-200 bg-white divide-y divide-slate-200"

  # Polymorphic slot: items are pre-built components, so the lambda just
  # passes them through to be rendered.
  renders_many :items, ->(item) { item }

  def initialize(css_class: nil)
    @css_class = css_class
  end

  def call
    return unless items?

    content_tag container_tag, class: @css_class || DEFAULT_CSS_CLASSES do
      safe_join(items)
    end
  end

  private

  def container_tag
    :ul
  end
end
