class FeedIdentificationActivity
  def initialize(identification, run_id: identification.run_id)
    @identification = identification
    @run_id = run_id
  end

  def start!
    create_event(status: "processing", candidates: [], diagnostics: {})
  end

  def finish!(status:, candidates: [], diagnostics: {})
    event = Event.where(type: "feed_identification", subject: identification)
                 .find_by("metadata ->> 'run_id' = ?", run_id)
    return if event && event.metadata["status"] != "processing"

    # A new ID lets the event log's cursor notice the completed attempt.
    Event.transaction do
      create_event(status: status.to_s, candidates: candidates, diagnostics: diagnostics)
      event&.destroy!
    end
  end

  def self.sanitize_url(value)
    uri = URI.parse(value.to_s)
    return "[invalid URL]" unless uri.is_a?(URI::HTTP)

    uri.userinfo = nil
    uri.query = nil
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    "[invalid URL]"
  end

  private

  attr_reader :identification, :run_id

  def create_event(status:, candidates:, diagnostics:)
    Event.create!(
      type: "feed_identification",
      level: :debug,
      user: identification.user,
      subject: identification,
      metadata: sanitize({
        input: self.class.sanitize_url(identification.input),
        run_id: run_id,
        status: status,
        candidates: candidates,
        diagnostics: diagnostics,
        stats: stats(status)
      })
    )
  end

  def stats(status)
    result = { started_at: identification.started_at }
    return result if status == "processing"

    result.merge(
      completed_at: Time.current,
      total_duration: identification.started_at && (Time.current - identification.started_at).round(3)
    )
  end

  # URLs can also appear inside transport errors and candidate titles.
  def sanitize(value)
    case value
    when Hash then value.transform_values { |item| sanitize(item) }
    when Array then value.map { |item| sanitize(item) }
    when String then value.gsub(%r{https?://[^\s<>"']+}) { |url| self.class.sanitize_url(url) }
    else value
    end
  end
end
