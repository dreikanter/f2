class AccessTokensController < ApplicationController
  def index
    authorize AccessToken
    @access_tokens = scope.order(created_at: :desc)
  end

  def show
    @access_token = find_access_token
    @feed = load_feed
    authorize @access_token
  end

  def new
    @access_token = AccessToken.new
    @feed = load_feed
    authorize @access_token
  end

  def create
    @access_token = build_acces_token
    @feed = load_feed
    authorize @access_token

    unless valid_host?(@access_token.host)
      render :new, status: :unprocessable_entity
      return
    end

    if @access_token.save
      @feed&.update_column(:access_token_id, @access_token.id)
      @access_token.validate_token_async
      redirect_to access_token_path(@access_token, feed_id: @feed&.id)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @access_token = find_access_token
    authorize @access_token
  end

  def update
    @access_token = find_access_token
    authorize @access_token

    new_token = params.dig(:access_token, :token).presence
    attrs = { name: params.dig(:access_token, :name) }
    attrs[:encrypted_token] = new_token if new_token

    if @access_token.update(attrs)
      @access_token.validate_token_async if new_token
      redirect_to access_token_path(@access_token), notice: "Changes saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    access_token = find_access_token
    authorize access_token
    access_token.destroy!
    redirect_to access_tokens_path, notice: "Access token '#{access_token.name}' has been deleted."
  end

  private

  def load_feed
    return nil if params[:feed_id].blank?

    Current.user.feeds.find_by(id: params[:feed_id])
  end

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
