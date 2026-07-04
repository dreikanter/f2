class JobRun < ApplicationRecord
  # Allowlist for job names arriving in params, so a request can't enqueue an
  # arbitrary class. Registered jobs take no arguments.
  RUNNABLE_JOBS = [
    AnthropicCapabilityProbeJob,
    KimiCapabilityProbeJob,
    KimiWebSearchWireJob,
    KimiStructuredOutputJob,
    KimiClientToolJob,
    PurgeExpiredEventsJob
  ].freeze

  enum :status, {
    queued: "queued",
    running: "running",
    succeeded: "succeeded",
    failed: "failed"
  }, default: :queued

  # Structured output recorded by the job while it runs (see RecordsJobRun).
  has_many :events, as: :subject, dependent: :nullify

  validates :job_class, presence: true

  def self.runnable_job(name)
    RUNNABLE_JOBS.find { |klass| klass.name == name }
  end
end
