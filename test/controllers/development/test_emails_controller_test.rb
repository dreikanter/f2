require "test_helper"

class Development::TestEmailsControllerTest < ActionDispatch::IntegrationTest
  def dev_user
    @dev_user ||= create(:user, :dev)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "#create should redirect unauthenticated users" do
    post development_email_preview_test_email_path("passwords_mailer-reset")

    assert_redirected_to new_session_path
  end

  test "#create should deny users without dev permission" do
    sign_in_as(regular_user)

    post development_email_preview_test_email_path("passwords_mailer-reset")

    assert_redirected_to root_path
  end

  test "#create should enqueue a test email to the current user and confirm" do
    sign_in_as(dev_user)

    assert_enqueued_with(job: EmailPreviewTestJob, args: ["passwords_mailer-reset", dev_user.email_address]) do
      post development_email_preview_test_email_path("passwords_mailer-reset")
    end

    assert_redirected_to development_email_preview_path("passwords_mailer-reset")
    assert_equal "Test email sent to #{dev_user.email_address}.", flash[:success]
  end

  test "#create should redirect for an unknown email type" do
    sign_in_as(dev_user)

    assert_no_enqueued_jobs do
      post development_email_preview_test_email_path("unknown-mailer")
    end

    assert_redirected_to development_email_previews_path
    assert_equal "Unknown email type.", flash[:alert]
  end
end
