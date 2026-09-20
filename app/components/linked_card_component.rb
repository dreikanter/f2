class LinkedCardComponent < CardComponent
  LINK_CLASSES = "block no-underline shadow-xs hover:bg-surface-muted hover:shadow-md transition duration-75"
  DISABLED_CLASSES = "opacity-50 cursor-not-allowed"

  def initialize(href:, title:, icon:, description:, disabled: false, tooltip: nil, **html_options)
    @href = href
    @title = title
    @icon = icon
    @description = description
    @disabled = disabled
    @tooltip = tooltip
    super(**html_options)
  end

  def before_render
    raise ArgumentError, "LinkedCardComponent takes title and description keywords, not a block" if content?
  end

  private

  def card_options
    options = merged_options
    options[:class] = helpers.class_names(options[:class], @disabled ? DISABLED_CLASSES : LINK_CLASSES)
    options[:title] = @tooltip
    if @disabled
      options.except(:target, :rel).merge(role: "link", aria: options.fetch(:aria, {}).merge(disabled: true))
    else
      options.merge(href: @href)
    end
  end

  # Built in Ruby because block helpers called through `helpers` capture into
  # the view context buffer, not the component one.
  def heading
    safe_join([
      helpers.icon(@icon, css_class: "mt-1 size-5"),
      tag.span(@title),
      (helpers.icon("external-link", css_class: "mt-1.5 size-4 text-muted") if opens_new_tab?)
    ].compact)
  end

  def opens_new_tab?
    !@disabled && @html_options[:target] == "_blank"
  end
end
