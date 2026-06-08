require "test_helper"

class Admin::SystemStatusControllerTest < ActionDispatch::IntegrationTest
  def dev_user
    @dev_user ||= create(:user, :dev)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "should redirect non-dev users" do
    login_as(regular_user)

    get admin_system_status_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "should redirect unauthenticated users" do
    get admin_system_status_path

    assert_redirected_to new_session_path
  end

  test "should show system status for dev users" do
    login_as(dev_user)

    get admin_system_status_path

    assert_response :success
  end

  test "should show configuration checklist" do
    login_as(dev_user)

    get admin_system_status_path

    assert_response :success
    assert_select "[data-key='config.resend_key']", text: /Resend key present/
    assert_select "[data-key='config.resend_signing_secret']", text: /Resend signing secret/
    assert_select "[data-key='config.honeybadger_key']", text: /Honeybadger/
    assert_select "[data-key='config.background_jobs']", text: /Background jobs/
  end

  test "should flag background jobs as healthy when a process is heartbeating" do
    SolidQueue::Process.create!(kind: "Worker", name: "worker-test", pid: 999, last_heartbeat_at: Time.current)
    login_as(dev_user)

    get admin_system_status_path

    assert_response :success
    assert_select "[data-key='config.background_jobs'][data-status='ok']"
  end

  test "should flag background jobs as a problem when no process is heartbeating" do
    SolidQueue::Process.delete_all
    login_as(dev_user)

    get admin_system_status_path

    assert_response :success
    assert_select "[data-key='config.background_jobs'][data-status='error']"
  end

  test "should show deployed version details" do
    with_release_env(
      "APP_REVISION" => "0123456789abcdef",
      "APP_REVISION_SHORT" => "0123456",
      "APP_DEPLOYED_AT" => "2026-05-09T12:34:56Z"
    ) do
      login_as(dev_user)

      get admin_system_status_path
    end

    assert_response :success
    assert_select "[data-key='release.revision.value'] code", text: "0123456"
    assert_select "[data-key='release.deployed_at.value'] code", text: /9 May 2026, 12:34/
    assert_select "[data-key='release.environment.value'] code", text: Rails.env
  end

  private

  def login_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

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
