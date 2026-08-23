class GroupsRefreshControlComponent < ViewComponent::Base
  TITLE = "Refresh groups".freeze
  TIMEOUT_NOTE = "This is taking longer than expected — try again in a moment.".freeze

  # The refresh control for a token's group list, in every state it can appear
  # in: idle, refreshing, and the timed-out fallback the polling controller
  # reveals once a refresh outlives its poll budget.
  #
  # Every state renders the same RefreshButtonComponent, so the control keeps
  # its box and nothing around it moves when the state changes. The refreshing
  # button is disabled, so it can't kick off a second refresh.
  #
  # Wiring the trigger stays with the caller — a form submit on the access token
  # page, a Stimulus click inside the feed form — and its attributes are passed
  # through. `key_prefix` namespaces the testing hooks ("access_token", "feed").
  def initialize(key_prefix:, refreshing: false, available: true, **trigger_attrs)
    @key_prefix = key_prefix
    @refreshing = refreshing
    @available = available
    @trigger_attrs = trigger_attrs
  end

  def render?
    refreshing || available
  end

  private

  attr_reader :key_prefix, :refreshing, :available

  def loading_button
    RefreshButtonComponent.new(title: TITLE, loading: true,
                               data: { polling_target: "content", key: "#{key_prefix}.groups-refreshing" })
  end

  # While a refresh runs the trigger waits out of sight, ready for the polling
  # controller to reveal it when the refresh takes longer than expected.
  def trigger_button
    attrs = @trigger_attrs.dup
    data = (attrs.delete(:data) || {}).merge(key: "#{key_prefix}.refresh-groups")
    data[:polling_target] = "timeoutMessage" if refreshing

    RefreshButtonComponent.new(title: TITLE, hidden: refreshing, data: data, **attrs)
  end

  def timeout_note_attributes
    {
      hidden: true,
      class: "w-full text-sm text-warning",
      data: { polling_target: "timeoutMessage", key: "#{key_prefix}.groups-refresh-timeout" }
    }
  end
end
