require "test_helper"

class Development::SystemStatusControllerTest < ActionDispatch::IntegrationTest
  def dev_user
    @dev_user ||= create(:user, :dev)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "should redirect non-dev users" do
    sign_in_as(regular_user)

    get development_system_status_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "should redirect unauthenticated users" do
    get development_system_status_path

    assert_redirected_to new_session_path
  end

  test "should show system status for dev users" do
    sign_in_as(dev_user)

    get development_system_status_path

    assert_response :success
  end

  test "should show configuration checklist" do
    sign_in_as(dev_user)

    get development_system_status_path

    assert_response :success
    assert_select "[data-key='config.resend_key']", text: /Resend key present/
    assert_select "[data-key='config.resend_signing_secret']", text: /Resend signing secret/
    assert_select "[data-key='config.honeybadger_key']", text: /Honeybadger/
    assert_select "[data-key='config.imgproxy_endpoint']", text: /imgproxy endpoint/
    assert_select "[data-key='config.imgproxy_key']", text: /imgproxy signing key/
    assert_select "[data-key='config.imgproxy_salt']", text: /imgproxy signing salt/
    assert_select "[data-key='config.metrics_push']", text: /Metrics push enabled/
    assert_select "[data-key='config.background_jobs']", text: /Background jobs/
  end

  test "should flag metrics push as healthy when METRICS_URL is set" do
    Metrics.stub(:enabled?, true) do
      sign_in_as(dev_user)

      get development_system_status_path
    end

    assert_response :success
    assert_select "[data-key='config.metrics_push'][data-status='ok']"
  end

  test "should flag metrics push as neutral when METRICS_URL is unset" do
    Metrics.stub(:enabled?, false) do
      sign_in_as(dev_user)

      get development_system_status_path
    end

    assert_response :success
    assert_select "[data-key='config.metrics_push'][data-status='neutral']"
  end

  test "should flag background jobs as healthy when a process is heartbeating" do
    SolidQueue::Process.create!(kind: "Worker", name: "worker-test", pid: 999, last_heartbeat_at: Time.current)
    sign_in_as(dev_user)

    get development_system_status_path

    assert_response :success
    assert_select "[data-key='config.background_jobs'][data-status='ok']"
  end

  test "should flag background jobs as a problem when no process is heartbeating" do
    SolidQueue::Process.delete_all
    sign_in_as(dev_user)

    get development_system_status_path

    assert_response :success
    assert_select "[data-key='config.background_jobs'][data-status='error']"
  end

  test "should show deployed version details" do
    with_release_env(
      "APP_REVISION" => "0123456789abcdef",
      "APP_REVISION_SHORT" => "0123456",
      "APP_DEPLOYED_AT" => "2026-05-09T12:34:56Z"
    ) do
      sign_in_as(dev_user)

      get development_system_status_path
    end

    assert_response :success
    assert_select "[data-key='release.revision.value'] a[href='#{F2Rails::GITHUB_REPO_URL}/commit/0123456789abcdef'] code", text: "0123456"
    assert_select "[data-key='release.deployed_at.value'] code", text: /9 May 2026, 12:34/
    assert_select "[data-key='release.environment.value'] span", text: Rails.env
  end

  private


  def with_release_env(values)
    previous_values = values.keys.index_with { |key| ENV.fetch(key, nil) }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous_values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
