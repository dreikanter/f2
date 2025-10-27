class ProfileMailer < ApplicationMailer
  def email_change_confirmation(user)
    @user = user
    @new_email = user.unconfirmed_email
    @token = user.generate_token_for(:change_email_confirmation)
    @confirmation_url = settings_email_confirmation_url(@token)

    message = mail(to: @new_email, subject: "Confirm your new email address")

    TransactionalEmailEventRecorder.attach_context(
      message: message,
      mailer: self.class.name,
      action: __method__,
      user: @user
    )

    message
  end

  def account_confirmation(user)
    @user = user
    @token = user.generate_token_for(:initial_email_confirmation)
    @confirmation_url = registration_email_confirmation_url(@token)

    message = mail(to: user.email_address, subject: "Confirm your email address")

    TransactionalEmailEventRecorder.attach_context(
      message: message,
      mailer: self.class.name,
      action: __method__,
      user: @user
    )

    message
  end
end
