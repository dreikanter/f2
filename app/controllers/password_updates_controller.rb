class PasswordUpdatesController < ApplicationController
  def edit
    @user = Current.user
  end

  def update
    @user = Current.user

    unless current_password_correct?
      redirect_with_incorrect_password
      return
    end

    if @user.update(password_params)
      redirect_with_success
    else
      redirect_with_validation_errors
    end
  end

  private

  def current_password_correct?
    current_password = params.dig(:user, :current_password)
    current_password.present? && @user.authenticate(current_password)
  end

  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end

  def redirect_with_incorrect_password
    redirect_to edit_settings_password_update_path, alert: "Current password is incorrect."
  end

  def redirect_with_success
    redirect_to settings_path, notice: "Password updated successfully."
  end

  def redirect_with_validation_errors
    redirect_to edit_settings_password_update_path, alert: @user.errors.full_messages.join(", ")
  end
end
