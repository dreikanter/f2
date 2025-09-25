class SettingsController < ApplicationController
  def show
    @user = Current.user
    @access_tokens = Current.user.access_tokens
  end
end
