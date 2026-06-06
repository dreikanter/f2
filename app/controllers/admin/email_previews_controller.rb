class Admin::EmailPreviewsController < ApplicationController
  CATALOG = [
    {
      id: "passwords_mailer-reset",
      label: "Password Reset",
      description: "Sent when someone requests a password reset"
    },
    {
      id: "profile_mailer-account_confirmation",
      label: "Account Confirmation",
      description: "Sent during signup to verify the email address"
    },
    {
      id: "profile_mailer-email_change_confirmation",
      label: "Email Change Confirmation",
      description: "Sent when a user requests an email address change"
    },
    {
      id: "test_mailer-ping",
      label: "Test Ping",
      description: "A minimal test email to verify delivery is working"
    }
  ].freeze

  def index
    authorize [:admin, :email_preview], :index?
    @previews = CATALOG
  end

  def show
    authorize [:admin, :email_preview], :show?
    @preview = CATALOG.find { _1[:id] == params[:id] }
    redirect_to(admin_email_previews_path, alert: "Unknown email type.") and return unless @preview

    message = build_message(params[:id])
    @subject = message.subject
    @html_body = message.html_part&.decoded
    @text_body = message.text_part&.decoded
  end

  private

  def build_message(id)
    ApplicationMailer.preview_mode = true
    user = sample_user

    case id
    when "passwords_mailer-reset"
      PasswordsMailer.reset(user).message
    when "profile_mailer-account_confirmation"
      ProfileMailer.account_confirmation(user).message
    when "profile_mailer-email_change_confirmation"
      ProfileMailer.email_change_confirmation(user).message
    when "test_mailer-ping"
      TestMailer.ping("preview@example.com").message
    end
  ensure
    ApplicationMailer.preview_mode = false
  end

  def sample_user
    user = User.new(
      email_address: "preview@example.com",
      name: "Sam Preview",
      password: "previewpassword",
      unconfirmed_email: "new.preview@example.com"
    )
    user.id = 0
    user
  end
end
