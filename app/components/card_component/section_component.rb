class CardComponent::SectionComponent < ViewComponent::Base
  BASE_CLASSES = "p-6"

  def initialize(**html_options)
    @html_options = html_options
  end

  def call
    content_tag(:div, content, merged_options)
  end

  private

  def merged_options
    classes = helpers.class_names(BASE_CLASSES, @html_options[:class])
    @html_options.merge(class: classes)
  end
end
