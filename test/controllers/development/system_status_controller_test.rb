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

  test "should show the effective mail sender" do
    sign_in_as(dev_user)

    get development_system_status_path

    assert_response :success
    assert_select "[data-key='configuration.mailer_from.label']", text: "From address"
    assert_select "[data-key='configuration.mailer_from.value'] code", text: "noreply@example.com"
  end

  test "should list every optional integration with its effective state" do
    sign_in_as(dev_user)

    get development_system_status_path

    assert_response :success
    assert_select "[data-key='integration.error_reporting.label']", text: "Error reporting"
    assert_select "[data-key='integration.image_proxy.label']", text: "Image proxy"
    assert_select "[data-key='integration.metrics.label']", text: "Metrics"
    assert_select "[data-key='integration.metrics.value']", text: "Off"
  end

  test "should show a configured integration as on" do
    Config.stub(:integrations, { metrics: true }) do
      sign_in_as(dev_user)

      get development_system_status_path
    end

    assert_response :success
    assert_select "[data-key='integration.metrics.value']", text: "On"
  end

  test "should show other tables total in table usage" do
    sign_in_as(dev_user)

    get development_system_status_path

    assert_response :success
    assert_select "[data-key='table_usage.other.label']", text: "Other"
    assert_select "[data-key='table_usage.other.value']"
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
    assert_select "[data-key='release.revision.value'] a[href='#{Feeder::GITHUB_REPO_URL}/commit/0123456789abcdef'] code", text: "0123456"
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
