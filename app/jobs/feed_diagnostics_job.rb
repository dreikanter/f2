class FeedDiagnosticsJob < ApplicationJob
  include RecordsJobRun
  include RunsAsMaintenanceJob

  def self.runnable_parameters = { feed_id: "Feed ID" }

  def self.description
    "Exports retained feed data, AI prompts and responses, events, and errors. Does not refresh or publish."
  end

  def perform(feed_id)
    report = FeedDiagnosticReport.new(Feed.find(feed_id)).call
    record_event(type: "job.feed_diagnostics.completed", message: "Diagnostics for feed #{feed_id}", **report)
  rescue ActiveRecord::RecordNotFound
    record_event(type: "job.feed_diagnostics.failed", message: "Feed not found.", level: :error)
    raise
  end
end
