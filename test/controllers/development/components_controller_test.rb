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

  test "#show should associate checkbox and radio labels with their controls" do
    get development_components_path

    # Clickable labels require a matching id/for pair (the production idiom).
    assert_select "input[type=checkbox]#enable_feed"
    assert_select "label[for=enable_feed]"

    assert_select "input[type=radio]#refresh_frequency_30m"
    assert_select "label[for=refresh_frequency_30m]"

    # Form-group label points at its input.
    assert_select "input[type=text]#group_feed_name"
    assert_select "label[for=group_feed_name]"
  end
end
