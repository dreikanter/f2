require "test_helper"

class Development::EmailPreviewsControllerTest < ActionDispatch::IntegrationTest
  def dev_user
    @dev_user ||= create(:user, :dev)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "#index should redirect unauthenticated users" do
    get development_email_previews_path

    assert_redirected_to new_session_path
  end

  test "#index should deny users without dev permission" do
    sign_in_as(regular_user)

    get development_email_previews_path

    assert_redirected_to root_path
  end

  test "#index should show email list for dev users" do
    sign_in_as(dev_user)

    get development_email_previews_path

    assert_response :success
    assert_select "h1", "Email Previews"
  end

  test "#show should redirect unauthenticated users" do
    get development_email_preview_path("passwords_mailer-reset")

    assert_redirected_to new_session_path
  end

  test "#show should deny users without dev permission" do
    sign_in_as(regular_user)

    get development_email_preview_path("passwords_mailer-reset")

    assert_redirected_to root_path
  end

  test "#show should redirect for unknown email type" do
    sign_in_as(dev_user)

    get development_email_preview_path("unknown-mailer")

    assert_redirected_to development_email_previews_path
  end

  %w[
    passwords_mailer-reset
    profile_mailer-account_confirmation
    profile_mailer-email_change_confirmation
    test_mailer-ping
  ].each do |id|
    test "#show should render preview for #{id}" do
      sign_in_as(dev_user)

      get development_email_preview_path(id)

      assert_response :success
    end
  end
end
