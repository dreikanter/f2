class PasswordUpdatesController < ApplicationController
  def update
    @user = Current.user

    unless current_password_correct?
      redirect_to profile_path, alert: "Current password is incorrect."
      return
    end

    if @user.update(password_params)
      redirect_to profile_path, notice: "Password updated successfully."
    else
      redirect_to profile_path, alert: @user.errors.full_messages.join(", ")
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
end
