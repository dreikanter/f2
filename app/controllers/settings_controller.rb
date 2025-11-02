class SettingsController < ApplicationController

  def show
    @user = Current.user
    authorize @user
    @access_tokens = policy_scope(AccessToken)
  end
end
