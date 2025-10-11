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
      send_confirmation_email
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

  def send_confirmation_email
    ProfileMailer.email_change_confirmation(@user, new_email).deliver_later
  end

  def redirect_with_invalid_email
    redirect_to edit_settings_email_update_path, alert: "Please enter a valid new email address."
  end

  def redirect_with_duplicate_email
    redirect_to edit_settings_email_update_path, alert: "Email address is already taken."
  end

  def redirect_with_confirmation_sent
    redirect_to settings_path, notice: "Email confirmation sent to <b>#{new_email}</b>."
  end
end
