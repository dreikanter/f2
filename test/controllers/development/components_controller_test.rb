require "test_helper"

class Development::ComponentsControllerTest < ActionDispatch::IntegrationTest
  test "dev tools should be enabled in the test environment" do
    assert Rails.configuration.x.dev_tools.enabled,
           "dev tools must be enabled so the component reference route is drawn"
  end

  test "#show should render the UI elements reference" do
    get development_components_path

    assert_response :success
    assert_select '[data-key="toc"]'
    assert_select '[data-key="section.buttons"]'
    assert_select '[data-key="section.form-group"]'
    assert_select '[data-key="section.page-header"]'
    assert_select '[data-key="section.event-description"]'
  end

  test "#show should not require authentication" do
    get development_components_path

    assert_response :success
  end
end
