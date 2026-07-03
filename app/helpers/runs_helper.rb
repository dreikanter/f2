module RunsHelper
  RUN_STATUS_COLORS = {
    "queued" => :gray,
    "running" => :blue,
    "succeeded" => :green,
    "failed" => :red
  }.freeze

  def run_status_badge(run)
    render BadgeComponent.new(
      text: run.status,
      color: RUN_STATUS_COLORS.fetch(run.status, :gray),
      key: "development.job_runs.#{run.id}.status"
    )
  end
end
