require "test_helper"

class Maintenance::JobsTest < ActionDispatch::IntegrationTest
  TOKEN = "test-maintenance-token".freeze

  setup do
    @previous_token = ENV["MAINTENANCE_JOB_TOKEN"]
    ENV["MAINTENANCE_JOB_TOKEN"] = TOKEN
  end

  teardown do
    ENV["MAINTENANCE_JOB_TOKEN"] = @previous_token
  end

  def auth
    { "Authorization" => "Bearer #{TOKEN}" }
  end

  test "is disabled with 404 when no token is configured" do
    ENV["MAINTENANCE_JOB_TOKEN"] = nil
    get maintenance_jobs_path, headers: auth
    assert_response :not_found
  end

  test "rejects a missing token" do
    get maintenance_jobs_path
    assert_response :unauthorized
  end

  test "rejects a wrong token" do
    get maintenance_jobs_path, headers: { "Authorization" => "Bearer nope" }
    assert_response :unauthorized
  end

  test "index lists the runnable jobs as plain text" do
    get maintenance_jobs_path, headers: auth

    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_includes response.body, "RedditRetrievalProbeJob"
    assert_includes response.body, "/maintenance/jobs/"
  end

  test "create runs the job inline and returns its events as text" do
    outcome = {
      results: [
        { check: "listing", status: "PASS", note: "2 scored posts", evidence: ["[1423 pts | 97% up | 218 comments] Ruby 3.4"], seconds: 0.3 },
        { check: "rss_control", status: "FAIL", note: "new.rss → HTTP 403", evidence: nil, seconds: 0.1 }
      ],
      passed: false
    }

    assert_difference -> { JobRun.count } => 1 do
      RedditRetrievalProbe.stub(:run, outcome) do
        post maintenance_job_runs_path("RedditRetrievalProbeJob"), headers: auth
      end
    end

    assert_response :success
    # The job completes (status succeeded); probe FAILs surface as events, not a
    # raised error.
    assert_equal "succeeded", JobRun.last.status
    assert_includes response.body, "RedditRetrievalProbeJob — run ##{JobRun.last.id}"
    assert_includes response.body, "listing: PASS"
    assert_includes response.body, "[1423 pts | 97% up | 218 comments] Ruby 3.4"
    assert_includes response.body, "rss_control: FAIL"
    assert_includes response.body, "listing=PASS rss_control=FAIL"
  end

  test "create rejects an unregistered job" do
    post maintenance_job_runs_path("Kernel"), headers: auth
    assert_response :not_found
  end

  test "show renders a past run scoped to its job" do
    run = create(:job_run, job_class: "RedditRetrievalProbeJob", status: "succeeded")
    create(:event, subject: run, type: "job.reddit_retrieval_probe.completed", level: :info, message: "listing=PASS")

    get maintenance_job_run_path("RedditRetrievalProbeJob", run.id), headers: auth

    assert_response :success
    assert_includes response.body, "run ##{run.id}"
    assert_includes response.body, "listing=PASS"
  end
end
