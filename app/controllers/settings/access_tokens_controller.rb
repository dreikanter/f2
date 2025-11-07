class Settings::AccessTokensController < ApplicationController
  def index
    authorize AccessToken
    @access_tokens = policy_scope(AccessToken).order(created_at: :desc)
  end

  def destroy
    access_token = find_access_token
    authorize access_token
    access_token.destroy!
    redirect_to settings_access_tokens_path, notice: "Access token '#{access_token.name}' has been deleted."
  end

  private

  def find_access_token
    policy_scope(AccessToken).find(params[:id])
  end
end
