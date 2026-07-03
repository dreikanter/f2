# One execution of a registered maintenance job, triggered from the dev area.
# Runs are enqueued through JobRunnerJob, which drives the status lifecycle.
class JobRun < ApplicationRecord
  # Allowlist of jobs that can be run from the browser. Registered jobs take no
  # arguments by design. Both controllers and the runner resolve names against
  # this list, so a request can never enqueue an arbitrary class.
  RUNNABLE_JOBS = [
    PurgeExpiredEventsJob
  ].freeze

  enum :status, {
    queued: "queued",
    running: "running",
    succeeded: "succeeded",
    failed: "failed"
  }, default: :queued

  validates :job_class, presence: true

  def self.runnable_job(name)
    RUNNABLE_JOBS.find { |klass| klass.name == name }
  end
end
