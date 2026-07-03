module JobRunsHelper
  JOB_RUN_STATUS_COLORS = {
    "queued" => :gray,
    "running" => :blue,
    "succeeded" => :green,
    "failed" => :red
  }.freeze

  def job_run_status_badge(run)
    render BadgeComponent.new(
      text: run.status,
      color: JOB_RUN_STATUS_COLORS.fetch(run.status, :gray),
      key: "development.job_runs.#{run.id}.status"
    )
  end

  EVENT_LEVEL_COLORS = {
    "debug" => :gray,
    "info" => :blue,
    "warning" => :orange,
    "error" => :red
  }.freeze

  def event_level_badge(event)
    render BadgeComponent.new(text: event.level, color: EVENT_LEVEL_COLORS.fetch(event.level, :gray))
  end
end
