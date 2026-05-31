class EventLogEntryComponent < ViewComponent::Base
  include EventLogEntryPresentation

  def initialize(event:, href:)
    @event = event
    @href = href
  end

  private

  attr_reader :event, :href
end
