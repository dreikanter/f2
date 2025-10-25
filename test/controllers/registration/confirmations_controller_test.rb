require "test_helper"

class Registration::ConfirmationsControllerTest < ActionDispatch::IntegrationTest
  test "should show resend confirmation form" do
    get new_registration_confirmation_url
    assert_response :success
    assert_select "h1", "Resend Confirmation Email"
  end

  test "should send confirmation email for inactive user" do
    inactive_user = create(:user, state: :inactive)

    assert_difference("ActionMailer::MailDeliveryJob.queue_adapter.enqueued_jobs.count", 1) do
      post registration_confirmations_url, params: { email_address: inactive_user.email_address }
    end

    job = ActionMailer::MailDeliveryJob.queue_adapter.enqueued_jobs.last
    assert_equal "ProfileMailer", job[:args][0]
    assert_equal "account_confirmation", job[:args][1]

    assert_redirected_to registration_confirmation_pending_path
    assert_equal "If an inactive account exists with that email, a confirmation link has been sent.", flash[:notice]
  end

  test "should not send confirmation email for active user but show same message" do
    active_user = create(:user, state: :active)

    assert_no_enqueued_emails do
      post registration_confirmations_url, params: { email_address: active_user.email_address }
    end

    assert_redirected_to registration_confirmation_pending_path
    assert_equal "If an inactive account exists with that email, a confirmation link has been sent.", flash[:notice]
  end

  test "should not send confirmation email for nonexistent user but show same message" do
    assert_no_enqueued_emails do
      post registration_confirmations_url, params: { email_address: "nonexistent@example.com" }
    end

    assert_redirected_to registration_confirmation_pending_path
    assert_equal "If an inactive account exists with that email, a confirmation link has been sent.", flash[:notice]
  end

  test "should normalize email for lookup" do
    inactive_user = create(:user, state: :inactive, email_address: "normalize-test@example.com")

    assert_difference("ActionMailer::MailDeliveryJob.queue_adapter.enqueued_jobs.count", 1) do
      post registration_confirmations_url, params: { email_address: "  NORMALIZE-TEST@EXAMPLE.COM  " }
    end

    assert_redirected_to registration_confirmation_pending_path
  end
end
