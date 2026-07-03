# Wraps a registered job so each run's status and timing land on its JobRun.
class JobRunnerJob < ApplicationJob
  queue_as :default

  def perform(job_run)
    job_run.update!(status: :running, started_at: Time.current)
    job_run.job_class.constantize.new.perform
    job_run.update!(status: :succeeded, finished_at: Time.current)
  rescue StandardError => e
    job_run.update!(status: :failed, finished_at: Time.current)
    Rails.error.report(e, context: { job_run_id: job_run.id, job_class: job_run.job_class })
    raise # surface to SolidQueue too, don't swallow
  end
end
