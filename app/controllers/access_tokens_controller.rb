class AccessTokensController < ApplicationController
  def index
    authorize AccessToken
    @access_tokens = scope.order(created_at: :desc)
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
    @access_token = build_acces_token
    authorize @access_token

    unless valid_host?(@access_token.host)
      render :new, status: :unprocessable_entity
      return
    end

    if @access_token.save
      @access_token.validate_token_async
      redirect_to settings_access_token_path(@access_token)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    access_token = find_access_token
    authorize access_token
    access_token.destroy!
    redirect_to settings_access_tokens_path, notice: "Access token '#{access_token.name}' has been deleted."
  end

  private

  def build_acces_token
    Current.user.access_tokens.build(**access_token_params, encrypted_token: access_token_params[:token])
  end

  def find_access_token
    scope.find(params[:id])
  end

  def scope
    policy_scope(AccessToken)
  end

  def access_token_params
    params.require(:access_token).permit(:name, :token, :host)
  end

  def valid_host?(host)
    AccessToken::FREEFEED_HOSTS.values.any? { |config| config[:url] == host }
  end
end
