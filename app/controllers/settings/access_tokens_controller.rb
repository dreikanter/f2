class Settings::AccessTokensController < ApplicationController
  def index
    authorize AccessToken
    @access_tokens = policy_scope(AccessToken).order(created_at: :desc)
  end

  def show
    @access_token = find_access_token
    authorize @access_token
  end

  def new
    @access_token = AccessToken.new
    authorize @access_token
  end

  def create
    # TODO: Implement access token creation
  end

  def edit
    @access_token = find_access_token
    authorize @access_token
  end

  def update
    # TODO: Implement access token update
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
