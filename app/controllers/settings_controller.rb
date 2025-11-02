class SettingsController < ApplicationController
  layout "tailwind"

  def show
    @user = Current.user
    authorize @user
    @access_tokens = policy_scope(AccessToken)
  end
end
