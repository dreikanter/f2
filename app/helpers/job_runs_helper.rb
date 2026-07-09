module JobRunsHelper
  JOB_RUN_STATUS_COLORS = {
    "queued" => :neutral,
    "running" => :info,
    "succeeded" => :success,
    "failed" => :danger
  }.freeze

  def job_run_status_badge(run)
    render BadgeComponent.new(
      text: run.status,
      color: JOB_RUN_STATUS_COLORS.fetch(run.status, :neutral),
      key: "development.job_runs.#{run.id}.status"
    )
  end

  EVENT_LEVEL_COLORS = {
    "debug" => :neutral,
    "info" => :info,
    "warning" => :warning,
    "error" => :danger
  }.freeze

  def event_level_badge(event)
    render BadgeComponent.new(text: event.level, color: EVENT_LEVEL_COLORS.fetch(event.level, :neutral))
  end
end
