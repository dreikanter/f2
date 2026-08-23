class RefreshButtonComponent < ViewComponent::Base
  BUTTON_CLASSES = "inline-flex shrink-0 items-center justify-center rounded-md border border-border bg-surface p-3 " \
    "text-body shadow-sm transition hover:bg-surface-muted focus:outline-none focus:ring-2 focus:ring-ring " \
    "focus:ring-offset-1 cursor-pointer disabled:cursor-not-allowed disabled:opacity-50".freeze

  # An icon refresh button with a spinner loading state.
  #
  # The loading state is the same button — same element, same classes, same box —
  # with the spinner swapped in for the static icon and clicks refused, so moving
  # between the two states can't shift the surrounding layout.
  #
  # It can be driven two ways. By default the button and its two icons are wired
  # as loading-button targets, so a loading-button Stimulus controller — mounted
  # on the button itself or an enclosing form — swaps the icons while a refresh
  # runs. Pass `loading: true` to render the loading state outright, for a
  # refresh the server already knows is in flight; such a button drives itself
  # and carries no loading-button targets.
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
  def initialize(title: "Refresh", loading: false, **attrs)
    @title = title
    @loading = loading
    @attrs = attrs
  end

  private

  def button_attributes
    attrs = @attrs.dup
    disabled = attrs.delete(:disabled) || @loading
    data = attrs.delete(:data) || {}
    {
      type: attrs.delete(:type) || "button",
      title: @title,
      disabled: disabled,
      class: [BUTTON_CLASSES, attrs.delete(:class)],
      data: @loading ? data : { loading_button_target: "button" }.merge(data)
    }.merge(attrs)
  end

  def icon_attributes(target, hidden:)
    {
      class: ("hidden" if hidden),
      data: @loading ? {} : { loading_button_target: target }
    }
  end
end
