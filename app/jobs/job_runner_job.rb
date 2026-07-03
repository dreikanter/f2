# Runs a registered maintenance job on behalf of a JobRun, driving its status
# lifecycle (queued -> running -> succeeded/failed). Running through SolidQueue
# keeps long maintenance work off the web request.
class JobRunnerJob < ApplicationJob
  queue_as :default

  def perform(job_run)
    job_run.update!(status: :running, started_at: Time.current)
    job_run.job_class.constantize.new.perform
    job_run.update!(status: :succeeded, finished_at: Time.current)
  rescue StandardError => e
    job_run.update!(status: :failed, finished_at: Time.current)
    Rails.error.report(e, context: { job_run_id: job_run.id, job_class: job_run.job_class })
    raise
  end
end
