class PasswordsMailer < ApplicationMailer
  def reset(user)
    return if user.email_deactivated?

    @user = user
    mail subject: "Reset your password", to: user.email_address
  end
end
