require "test_helper"

class RedditRetrievalProbeJobTest < ActiveJob::TestCase
  def job
    @job ||= RedditRetrievalProbeJob.new
  end

  def job_run
    @job_run ||= create(:job_run, job_class: "RedditRetrievalProbeJob", job_id: job.job_id)
  end

  test "should register as a runnable job" do
    assert_includes JobRun::RUNNABLE_JOBS, RedditRetrievalProbeJob
  end

  test "#perform should record one event per check plus a summary" do
    job_run

    outcome = {
      results: [
        { check: "listing", status: "PASS", note: "2 scored posts", evidence: ["[100 pts]"], seconds: 0.3 },
        { check: "rss_control", status: "FAIL", note: "new.rss → HTTP 403", evidence: nil, seconds: 0.1 }
      ],
      passed: false
    }

    RedditRetrievalProbe.stub(:run, outcome) do
      job.perform_now
    end

    checks = Event.for_subject(job_run).where(type: "job.reddit_retrieval_probe.check").order(:id)
    assert_equal 2, checks.count
    assert_predicate checks.first, :info?
    assert_predicate checks.second, :warning?
    assert_includes checks.second.message, "rss_control: FAIL"

    summary = Event.for_subject(job_run).find_by(type: "job.reddit_retrieval_probe.completed")
    assert_includes summary.message, "listing=PASS rss_control=FAIL"
    assert_equal false, summary.metadata["passed"]
    assert_predicate summary, :warning?
  end

  test "#perform should mark the summary info when every check passes" do
    job_run
    outcome = { results: [{ check: "listing", status: "PASS", note: "ok", evidence: [], seconds: 0.1 }], passed: true }

    RedditRetrievalProbe.stub(:run, outcome) do
      job.perform_now
    end

    summary = Event.for_subject(job_run).find_by(type: "job.reddit_retrieval_probe.completed")
    assert_predicate summary, :info?
    assert_equal true, summary.metadata["passed"]
  end
end
