require "test_helper"

class RecordsJobRunTest < ActiveJob::TestCase
  class TrackedTestJob < ApplicationJob
    cattr_accessor :should_raise, default: false
    include RecordsJobRun

    def perform
      record_event(type: "test.event", message: "did work", count: 1)
      raise "boom" if should_raise

      :done
    end
  end

  test "should drive status and record events when a JobRun matches the job_id" do
    job = TrackedTestJob.new
    run = create(:job_run, job_class: "TrackedTestJob", job_id: job.job_id)

    result = job.perform_now

    assert_equal :done, result
    run.reload
    assert_predicate run, :succeeded?
    assert_not_nil run.started_at
    assert_not_nil run.finished_at

    event = run.events.first
    assert_equal "test.event", event.type
    assert_equal "did work", event.message
    assert_equal({ "count" => 1 }, event.metadata)
    assert_equal run, event.subject
  end

  test "should run normally and record nothing without a matching JobRun" do
    assert_no_difference -> { Event.count } do
      assert_equal :done, TrackedTestJob.new.perform_now
    end
  end

  test "should mark the run failed and re-raise when perform errors" do
    TrackedTestJob.should_raise = true
    job = TrackedTestJob.new
    run = create(:job_run, job_class: "TrackedTestJob", job_id: job.job_id)

    assert_raises(RuntimeError) { job.perform_now }

    assert_predicate run.reload, :failed?
  ensure
    TrackedTestJob.should_raise = false
  end
end
