require "test_helper"

# Account and settings forms put the cursor in their first field on load,
# which browsers do natively from the autofocus attribute. These lock the
# markup in so a form can't quietly lose it.
class FormAutofocusTest < ActionDispatch::IntegrationTest
  UNFOCUSABLE_INPUT_TYPES = %w[hidden submit button image reset].freeze

  def user
    @user ||= create(:user)
  end

  test "sign in form autofocuses the email field" do
    get new_session_path
    assert_autofocus_on_first_field "email_address"
  end

  test "forgot password form autofocuses the email field" do
    get new_password_path
    assert_autofocus_on_first_field "email_address"
  end

  test "password reset form autofocuses the new password field" do
    get edit_password_path(user.generate_token_for(:password_reset))
    assert_autofocus_on_first_field "password"
  end

  test "registration form autofocuses the email field" do
    get registration_path(code: create(:invite).id)
    assert_autofocus_on_first_field "user_email_address"
  end

  test "resend confirmation form autofocuses the email field" do
    get new_registration_confirmation_path
    assert_autofocus_on_first_field "email_address"
  end

  test "change password form autofocuses the current password field" do
    sign_in_as(user)
    get edit_settings_password_update_path
    assert_autofocus_on_first_field "user_current_password"
  end

  test "change email form autofocuses the new email field" do
    sign_in_as(user)
    get edit_settings_email_update_path
    assert_autofocus_on_first_field "user_email_address"
  end

  test "new access token form autofocuses the instance field" do
    sign_in_as(user)
    get new_access_token_path
    assert_autofocus_on_first_field "access_token_host"
  end

  test "edit access token form autofocuses the name field" do
    sign_in_as(user)
    get edit_access_token_path(create(:access_token, user: user))
    assert_autofocus_on_first_field "access_token_name"
  end

  private

  def assert_autofocus_on_first_field(expected_id)
    assert_response :success

    autofocused = Nokogiri::HTML(response.body).css("[autofocus]")
    assert_equal 1, autofocused.size, "expected exactly one autofocused element on the page"
    assert_equal expected_id, autofocused.first["id"], "autofocus is on an unexpected field"

    form = autofocused.first.ancestors("form").first
    assert_equal expected_id, first_field(form)&.[]("id"), "autofocus is not on the form's first field"
  end

  def first_field(form)
    form.css("input, select, textarea").find do |field|
      next false if field["disabled"]

      field.name != "input" || UNFOCUSABLE_INPUT_TYPES.exclude?(field["type"])
    end
  end
end
