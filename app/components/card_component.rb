class CardComponent < ViewComponent::Base
  DEFAULT_BASE_CLASSES = "rounded-lg border border-slate-200 px-4 py-3 shadow-sm"

  def initialize(**html_options)
    @html_options = html_options
  end

  def call
    content_tag :div, content, merged_options
  end

  private

  def merged_options
    @html_options.merge(class: helpers.class_names(DEFAULT_BASE_CLASSES, @html_options[:class]))
  end
end
