class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  # One line shown above the job's run history in the dev area, for what a
  # maintenance job needs before it can run. Nil when the name says enough.
  # Rendered as HTML, so a description with markup composes it through `helpers`
  # and every interpolated value stays escaped.
  def self.description = nil

  # The view's tag builders, for descriptions that carry markup.
  def self.helpers = ApplicationController.helpers

  # Arguments the dev area launches this job with. Jobs that act on behalf of
  # whoever pressed Run override it to receive them.
  def self.runnable_arguments(_user) = []

  # Count every job run by outcome. A run that deferred itself for rate limiting
  # (RateLimited#rate_limited?) is throttled, not a real failure — it returns
  # normally after rescheduling, so we read the flag rather than catch anything.
  around_perform do |job, block|
    block.call
    status = job.try(:rate_limited?) ? "throttled" : "ok"
    Metrics.increment("job_executions_total", job: job.class.name, status: status)
  rescue StandardError
    Metrics.increment("job_executions_total", job: job.class.name, status: "error")
    raise
  end
end
