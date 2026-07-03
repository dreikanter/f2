require "test_helper"

class Development::JobsControllerTest < ActionDispatch::IntegrationTest
  def dev_user
    @dev_user ||= create(:user, :dev)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "#index should require authentication" do
    get development_jobs_path

    assert_redirected_to new_session_path
  end

  test "#index should require dev permission" do
    sign_in_as(regular_user)
    get development_jobs_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "#index should list registered jobs" do
    sign_in_as(dev_user)
    get development_jobs_path

    assert_response :success
    assert_select '[data-key="development.jobs.PurgeExpiredEventsJob"]'
    assert_select "a[href='#{development_job_job_runs_path("PurgeExpiredEventsJob")}']"
  end
end
