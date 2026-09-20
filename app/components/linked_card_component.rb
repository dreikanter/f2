class LinkedCardComponent < ViewComponent::Base
  LINK_CLASSES = "block no-underline shadow-xs hover:bg-surface-muted hover:shadow-md transition duration-75"
  DISABLED_CLASSES = "opacity-50 cursor-not-allowed"

  def initialize(href:, title:, icon:, description:, disabled: false, tooltip: nil, **html_options)
    @href = href
    @title = title
    @icon = icon
    @description = description
    @disabled = disabled
    @tooltip = tooltip
    @html_options = html_options
  end

  private

  def card_options
    options = @html_options.merge(
      class: helpers.class_names(
        CardComponent::BASE_CLASSES,
        CardComponent::PADDED_CLASSES,
        @disabled ? DISABLED_CLASSES : LINK_CLASSES,
        @html_options[:class]
      ),
      title: @tooltip
    )
    if @disabled
      options.except(:href, :target, :rel).merge("aria-disabled": "true")
    else
      options.merge(href: @href)
    end
  end

  def opens_new_tab?
    !@disabled && @html_options[:target] == "_blank"
  end
end
