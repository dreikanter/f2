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

  test "#create should enqueue the job and store its job_id on the run" do
    sign_in_as(dev_user)

    assert_difference -> { JobRun.count }, 1 do
      assert_enqueued_with(job: PurgeExpiredEventsJob) do
        post development_job_job_runs_path("PurgeExpiredEventsJob")
      end
    end

    run = JobRun.last
    assert_redirected_to development_job_job_runs_path("PurgeExpiredEventsJob")
    assert_equal "PurgeExpiredEventsJob", run.job_class
    assert run.job_id.present?
  end

  test "#show should render the run's recorded events" do
    run = create(:job_run, job_class: "PurgeExpiredEventsJob", status: :succeeded)
    event = create(:event, subject: run, message: "Purged 3 expired events")
    sign_in_as(dev_user)
    get development_job_job_run_path("PurgeExpiredEventsJob", run)

    assert_response :success
    assert_select %([data-key="development.job_runs.#{run.id}.event.#{event.id}"]), text: /Purged 3 expired events/
  end

  test "#show should require dev permission" do
    run = create(:job_run, job_class: "PurgeExpiredEventsJob")
    sign_in_as(regular_user)
    get development_job_job_run_path("PurgeExpiredEventsJob", run)

    assert_redirected_to root_path
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
