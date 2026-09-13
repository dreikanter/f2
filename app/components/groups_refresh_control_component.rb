class GroupsRefreshControlComponent < ViewComponent::Base
  TITLE = "Refresh groups".freeze
  TIMEOUT_NOTE = "This is taking longer than expected — try again in a moment.".freeze

  # The refresh control for a token's group list. An overdue response shows the
  # timeout note immediately; the polling controller can also reveal it when
  # its poll budget runs out.
  #
  # Idle and refreshing states use RefreshButtonComponent, so the control
  # keeps its size when a refresh starts. The refreshing
  # button is disabled, so it can't kick off a second refresh.
  #
  # Wiring the trigger stays with the caller (a form submit on the access token
  # page, a Stimulus click inside the feed form), and its attributes are passed
  # through. `key_prefix` namespaces the testing hooks ("access_token", "feed").
  def initialize(key_prefix:, refreshing: false, overdue: false, available: true, compact: false, **trigger_attrs)
    @key_prefix = key_prefix
    @refreshing = refreshing
    @overdue = overdue
    @available = available
    @compact = compact
    @trigger_attrs = trigger_attrs
  end

  def render?
    refreshing || overdue || available
  end

  private

  attr_reader :key_prefix, :refreshing, :overdue, :available

  def loading_button
    RefreshButtonComponent.new(title: TITLE, loading: true, compact: @compact,
                               data: { polling_target: "content", key: "#{key_prefix}.groups-refreshing" })
  end

  # While a refresh runs the trigger waits out of sight, ready for the polling
  # controller to reveal it when the refresh takes longer than expected.
  def trigger_button
    attrs = @trigger_attrs.dup
    data = (attrs.delete(:data) || {}).merge(key: "#{key_prefix}.refresh-groups")
    data[:polling_target] = "timeoutMessage" if refreshing

    RefreshButtonComponent.new(title: TITLE, compact: @compact, hidden: refreshing, data: data, **attrs)
  end

  def timeout_note_attributes
    {
      hidden: !overdue,
      class: "w-full text-sm text-warning",
      data: { polling_target: "timeoutMessage", key: "#{key_prefix}.groups-refresh-timeout" }
    }
  end
end
