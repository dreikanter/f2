class ProfileMailer < ApplicationMailer
  def email_change_confirmation(user, new_email)
    @user = user
    @new_email = new_email
    @token = user.generate_token_for(:email_change)
    @confirmation_url = email_confirmation_url(@token, new_email: @new_email)

    mail(to: @new_email, subject: "Confirm your new email address")
  end

  def account_confirmation(user)
    @user = user
    @token = user.generate_token_for(:email_confirmation)
    @confirmation_url = email_confirmation_url(@token)

    mail(to: user.email_address, subject: "Confirm your email address")
  end
end
