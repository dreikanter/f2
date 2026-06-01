class StatsBarComponent < ViewComponent::Base
  DEFAULT_CSS_CLASSES = "overflow-hidden md:flex md:divide-x md:divide-slate-200 rounded-lg border border-slate-200 bg-white"

  # Polymorphic slot: items are pre-built components, so the lambda just
  # passes them through to be rendered.
  renders_many :items, ->(item) { item }

  def initialize(css_class: nil)
    @css_class = css_class
  end

  def call
    return unless items?

    content_tag :dl, class: @css_class || DEFAULT_CSS_CLASSES do
      safe_join(items)
    end
  end
end
