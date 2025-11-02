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

    unless @user.can_change_email?
      redirect_with_rate_limit
      return
    end

    if @user.update(unconfirmed_email: new_email)
      ProfileMailer.email_change_confirmation(@user).deliver_later
      redirect_with_confirmation_sent
    else
      redirect_with_duplicate_email
    end
  end

  private

  def new_email
    params.dig(:user, :email_address)
  end

  def valid_email_change?
    new_email.present? && new_email != @user.email_address
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

  def redirect_with_rate_limit
    time_remaining = helpers.time_distance(@user.time_until_email_change_allowed)
    redirect_to edit_settings_email_update_path, alert: "You can change your email again in #{time_remaining}."
  end
end
