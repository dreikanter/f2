module Maintenance
  # Renders a JobRun and its recorded events as compact plain text for the
  # curl/agent maintenance interface — one line per event, evidence indented
  # beneath it, no HTML or framing noise.
  class JobRunReport
    def initialize(run)
      @run = run
    end

    def to_text
      [header, "", *event_lines].join("\n")
    end

    private

    def header
      "#{@run.job_class} — run ##{@run.id} — #{@run.status}#{duration_suffix}"
    end

    def duration_suffix
      return "" unless @run.started_at && @run.finished_at

      " (#{(@run.finished_at - @run.started_at).round(1)}s)"
    end

    def event_lines
      @run.events.order(:created_at, :id).flat_map { |event| format_event(event) }
    end

    # "!" flags anything above info so failures are scannable at a glance.
    def format_event(event)
      marker = event.level.to_s == "info" ? " " : "!"
      [" #{marker} #{event.message}", *evidence_lines(event)]
    end

    def evidence_lines(event)
      evidence = event.metadata["evidence"]
      return [] if evidence.blank?

      Array(evidence).map { |item| "      • #{item.to_s[0, 300]}" }
    end
  end
end
