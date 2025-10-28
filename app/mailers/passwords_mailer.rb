class PasswordsMailer < ApplicationMailer
  after_action :register_event

  def reset(user)
    @user = user
    set_event_context(user_id: user.id)
    mail(subject: "Reset your password", to: user.email_address)
  end
end
