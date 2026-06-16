class CollapsibleSectionComponent < ViewComponent::Base
  def initialize(title:, open: false, **html_options)
    @title = title
    @open = open
    @html_options = html_options
  end

  private

  def container_options
    options = @html_options.merge(class: helpers.class_names("group", @html_options[:class]))
    options[:open] = true if @open
    options
  end
end
