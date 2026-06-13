require "test_helper"

class Development::ComponentsControllerTest < ActionDispatch::IntegrationTest
  def dev_user
    @dev_user ||= create(:user, :dev)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "#show should render the UI elements reference" do
    login_as(dev_user)

    get development_components_path

    assert_response :success
    assert_select '[data-key="toc"]'
    assert_select '[data-key="section.buttons"]'
    assert_select '[data-key="section.date-time"]'
    assert_select '[data-key="section.date-time"] input[data-controller="datepicker"]'
    assert_select '[data-key="section.date-time"] input[type="time"]'
    assert_select '[data-key="section.form-group"]'
    assert_select '[data-key="section.page-header"]'
    assert_select '[data-key="section.event-description"]'
  end

  test "#show should require authentication" do
    get development_components_path

    assert_redirected_to new_session_path
  end

  test "#show should require dev permission" do
    login_as(regular_user)

    get development_components_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "#show should associate checkbox and radio labels with their controls" do
    login_as(dev_user)

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

  private

  def login_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end
end
