class SettingsController < ApplicationController
  def show
    @user = Current.user
    authorize @user
  end
end
