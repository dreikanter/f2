class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    mail(subject: "Reset your password", to: user.email_address).tap do |message|
      record_transactional_email_event(action: __method__, user: user, message: message)
    end
  end
end
