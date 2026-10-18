require "test_helper"

class RateLimitedTest < ActiveJob::TestCase
  class ThrottledJob < ApplicationJob
    include RateLimited

    def perform
      reschedule_for_rate_limit(3)
    end
  end

  class HookJob < ApplicationJob
    include RateLimited

    cattr_accessor :exhausted_with

    def perform
      reschedule_for_rate_limit(3)
    end

    private

    def on_rate_limit_exhausted(error)
      self.class.exhausted_with = error
    end
  end

  test "#reschedule_for_rate_limit reschedules the job within the attempt cap" do
    assert_enqueued_with(job: ThrottledJob) do
      ThrottledJob.perform_now
    end
  end

  test "#reschedule_for_rate_limit marks the run as rate limited" do
    job = ThrottledJob.new
    job.perform_now

    assert job.rate_limited?
  end

  test "#rate_limited? should be false for a run that was not throttled" do
    assert_not ThrottledJob.new.rate_limited?
  end

  test "a throttled run is counted as throttled rather than ok" do
    increments = []
    Metrics.stub(:increment, ->(name, **tags) { increments << [name, tags] }) do
      ThrottledJob.perform_now
    end

    statuses = increments.select { |name, _| name == "job_executions_total" }.map { |_, tags| tags[:status] }
    assert_equal ["throttled"], statuses
  end

  test "#reschedule_for_rate_limit should stop without reporting a bug at the attempt cap" do
    job = ThrottledJob.new
    job.executions = RateLimited::MAX_ATTEMPTS

    reports = capture_error_reports do
      assert_no_enqueued_jobs { job.perform_now }
    end

    assert_empty reports
    assert_predicate job, :rate_limited?
  end

  test "#reschedule_for_rate_limit invokes on_rate_limit_exhausted once the attempt cap is reached" do
    HookJob.exhausted_with = nil
    job = HookJob.new
    job.executions = RateLimited::MAX_ATTEMPTS

    assert_no_enqueued_jobs { job.perform_now }

    assert_instance_of RateLimit::Throttled, HookJob.exhausted_with
  end
end
