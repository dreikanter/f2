class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    message = mail subject: "Reset your password", to: user.email_address

    TransactionalEmailEventRecorder.attach_context(
      message: message,
      mailer: self.class.name,
      action: __method__,
      user: @user
    )

    message
  end
end
