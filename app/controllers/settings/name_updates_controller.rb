class Settings::NameUpdatesController < ApplicationController
  def edit
    @user = Current.user
  end

  def update
    @user = Current.user

    if @user.update(name: params.dig(:user, :name).to_s)
      redirect_with_success
    else
      redirect_with_validation_errors
    end
  end

  private

  def redirect_with_success
    redirect_to settings_path, success: "Name updated."
  end

  def redirect_with_validation_errors
    redirect_to edit_settings_name_update_path, alert: @user.errors.full_messages.join(", ")
  end
end
