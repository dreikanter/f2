require "test_helper"

class Development::JobRunsControllerTest < ActionDispatch::IntegrationTest
  def dev_user
    @dev_user ||= create(:user, :dev)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "#index should require dev permission" do
    sign_in_as(regular_user)
    get development_job_job_runs_path("PurgeExpiredEventsJob")

    assert_redirected_to root_path
  end

  test "#index should list runs for the job" do
    run = create(:job_run, job_class: "PurgeExpiredEventsJob", status: :succeeded)
    sign_in_as(dev_user)
    get development_job_job_runs_path("PurgeExpiredEventsJob")

    assert_response :success
    assert_select %([data-key="development.job_runs.#{run.id}"])
  end

  test "#index should return not found for an unregistered job" do
    sign_in_as(dev_user)
    get development_job_job_runs_path("SomeOtherJob")

    assert_response :not_found
  end

  test "#create should enqueue a run and redirect" do
    sign_in_as(dev_user)

    assert_difference -> { JobRun.count }, 1 do
      assert_enqueued_with(job: JobRunnerJob) do
        post development_job_job_runs_path("PurgeExpiredEventsJob")
      end
    end

    assert_redirected_to development_job_job_runs_path("PurgeExpiredEventsJob")
    assert_equal "PurgeExpiredEventsJob", JobRun.last.job_class
  end

  test "#create should require dev permission" do
    sign_in_as(regular_user)

    assert_no_difference -> { JobRun.count } do
      post development_job_job_runs_path("PurgeExpiredEventsJob")
    end

    assert_redirected_to root_path
  end

  test "#create should return not found for an unregistered job" do
    sign_in_as(dev_user)

    assert_no_difference -> { JobRun.count } do
      post development_job_job_runs_path("SomeOtherJob")
    end

    assert_response :not_found
  end
end
