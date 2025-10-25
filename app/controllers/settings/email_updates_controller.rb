class Settings::EmailUpdatesController < ApplicationController
  def edit
    @user = Current.user
  end

  def update
    @user = Current.user

    unless valid_email_change?
      redirect_with_invalid_email
      return
    end

    if email_already_taken?
      redirect_with_duplicate_email
    else
      save_unconfirmed_email_and_send_confirmation
      redirect_with_confirmation_sent
    end
  end

  private

  def new_email
    params.dig(:user, :email_address)
  end

  def valid_email_change?
    new_email.present? && new_email != @user.email_address
  end

  def email_already_taken?
    User.exists?(email_address: new_email)
  end

  def save_unconfirmed_email_and_send_confirmation
    @user.update!(unconfirmed_email: new_email)
    ProfileMailer.email_change_confirmation(@user).deliver_later
  end

  def redirect_with_invalid_email
    redirect_to edit_settings_email_update_path, alert: "Please enter a valid new email address."
  end

  def redirect_with_duplicate_email
    redirect_to edit_settings_email_update_path, alert: "Email address is already taken."
  end

  def redirect_with_confirmation_sent
    redirect_to settings_path, notice: "Email confirmation sent to <b>#{@user.unconfirmed_email}</b>."
  end
end
