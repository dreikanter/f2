class RefreshButtonComponent < ViewComponent::Base
  BUTTON_CLASSES = "inline-flex items-center justify-center rounded-md border border-border bg-surface " \
    "text-body shadow-sm transition hover:bg-surface-muted focus:outline-none focus:ring-2 focus:ring-ring " \
    "focus:ring-offset-1 cursor-pointer disabled:cursor-not-allowed disabled:opacity-50".freeze

  # An icon refresh button with a built-in spinner loading state.
  #
  # The button and its two icons are wired as loading-button targets, so a
  # loading-button Stimulus controller — mounted on the button itself or an
  # enclosing form — swaps the static icon for a spinner while a refresh runs.
  #
  # The trigger is the caller's concern: pass whatever attributes it needs and
  # they're merged onto the button. For example, a polling refresh:
  #
  #   render RefreshButtonComponent.new(data: {
  #     controller: "refresh-trigger loading-button",
  #     refresh_trigger_target_id_value: EventsListComponent::DOM_ID,
  #     action: "click->refresh-trigger#trigger"
  #   })
  #
  # or a form submit, where the form hosts the loading-button controller:
  #
  #   render RefreshButtonComponent.new(title: "Refresh now", type: "submit")
  #
  # `padding` sizes the button: the default suits page headers, "p-1.5" makes
  # a compact inline control (e.g. next to a form label).
  def initialize(title: "Refresh", padding: "p-3", **attrs)
    @title = title
    @padding = padding
    @attrs = attrs
  end

  private

  def button_attributes
    attrs = @attrs.dup
    {
      type: attrs.delete(:type) || "button",
      title: @title,
      class: [BUTTON_CLASSES, @padding, attrs.delete(:class)],
      data: { loading_button_target: "button" }.merge(attrs.delete(:data) || {})
    }.merge(attrs)
  end
end
