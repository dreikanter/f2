# Persists a job's execution to a JobRun when it was launched from the dev area.
#
# The launching controller stores the ActiveJob job_id on a JobRun row, so a job
# that includes this can find its run by that id, drive the status lifecycle, and
# record structured output as Events subject to the run. Jobs run outside the dev
# UI have no matching JobRun, so everything here no-ops and the job runs normally.
module RecordsJobRun
  extend ActiveSupport::Concern

  included do
    around_perform :track_job_run
  end

  private

  def job_run
    return @job_run if defined?(@job_run)

    @job_run = JobRun.find_by(job_id: job_id)
  end

  def record_event(type:, message: "", level: :info, **metadata)
    return unless job_run

    Event.create!(type: type, subject: job_run, level: level, message: message, metadata: metadata)
  end

  def track_job_run
    return yield unless job_run

    job_run.update!(status: :running, started_at: Time.current)
    result = yield
    job_run.update!(status: :succeeded, finished_at: Time.current)
    result
  rescue StandardError
    job_run.update!(status: :failed, finished_at: Time.current)
    raise
  end
end
