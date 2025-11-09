class Settings::AccessTokensController < ApplicationController
  UnsupportedFreeFeedHostError = Class.new(StandardError)

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
    @access_token = Current.user.access_tokens.build(**access_token_params, encrypted_token: access_token_params[:token])
    authorize @access_token
    raise UnsupportedFreeFeedHostError unless valid_host?(@access_token.host)

    if @access_token.save
      @access_token.validate_token_async
      redirect_to settings_access_token_path(@access_token)
    else
      render :new, status: :unprocessable_entity
    end
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

  def access_token_params
    params.require(:access_token).permit(:name, :token, :host)
  end

  def valid_host?(host)
    AccessToken::FREEFEED_HOSTS.values.any? { |config| config[:url] == host }
  end
end
