class PageDownloadFailureRecorder
  def initialize(event:, context: {})
    @event = event
    @context = context
  end

  def call(error)
    Event.transaction do
      failure = Event.create!(
        type: "page_download_failed",
        level: :warning,
        subject: @event.subject,
        user: @event.user,
        message: error.message,
        metadata: { stats: @context.merge(error.details) }
      )
      @event.event_references.create!(reference: failure)
    end
  end
end
