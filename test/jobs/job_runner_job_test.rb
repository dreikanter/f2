require "test_helper"

class JobRunnerJobTest < ActiveJob::TestCase
  class BoomJob
    def perform
      raise "boom"
    end
  end

  test "#perform should drive the run to succeeded" do
    run = create(:job_run)

    JobRunnerJob.perform_now(run)

    run.reload
    assert_predicate run, :succeeded?
    assert_not_nil run.started_at
    assert_not_nil run.finished_at
  end

  test "#perform should mark the run failed and re-raise when the job errors" do
    run = create(:job_run, job_class: "JobRunnerJobTest::BoomJob")

    assert_raises(RuntimeError) { JobRunnerJob.perform_now(run) }

    run.reload
    assert_predicate run, :failed?
    assert_not_nil run.finished_at
  end
end
