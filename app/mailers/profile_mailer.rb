class ProfileMailer < ApplicationMailer
  def email_change_confirmation(user)
    return if user.email_deactivated?

    @user = user
    @new_email = user.unconfirmed_email
    @token = user.generate_token_for(:change_email_confirmation)
    @confirmation_url = settings_email_confirmation_url(@token)

    mail(to: @new_email, subject: "Confirm your new email address")
  end

  def account_confirmation(user)
    return if user.email_deactivated?

    @user = user
    @token = user.generate_token_for(:initial_email_confirmation)
    @confirmation_url = registration_email_confirmation_url(@token)

    mail(to: user.email_address, subject: "Confirm your email address")
  end
end
