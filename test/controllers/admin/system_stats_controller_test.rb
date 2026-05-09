require "test_helper"

class Admin::SystemStatsControllerTest < ActionDispatch::IntegrationTest
  def admin_user
    @admin_user ||= begin
      user = create(:user)
      create(:permission, user: user, name: "admin")
      user
    end
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "should redirect non-admin users" do
    login_as(regular_user)

    get admin_system_stats_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "should redirect unauthenticated users" do
    get admin_system_stats_path

    assert_redirected_to new_session_path
  end

  test "should show system stats for admin users" do
    login_as(admin_user)

    get admin_system_stats_path

    assert_response :success
  end

  test "should show deployed version details" do
    with_release_env(
      "APP_REVISION" => "0123456789abcdef",
      "APP_REVISION_SHORT" => "0123456",
      "APP_DEPLOYED_AT" => "2026-05-09T12:34:56Z"
    ) do
      login_as(admin_user)

      get admin_system_stats_path
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
