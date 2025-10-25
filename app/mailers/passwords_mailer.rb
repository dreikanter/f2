class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    abort_if_email_deactivated!
    mail subject: "Reset your password", to: user.email_address
  end

  private

  def abort_if_email_deactivated!
    throw :abort if @user&.email_deactivated?
  end
end
