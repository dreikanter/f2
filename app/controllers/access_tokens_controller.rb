class AccessTokensController < ApplicationController
  def index
    @access_tokens = ordered_access_tokens
  end

  def new
    @access_token = AccessToken.new(host: AccessToken::FREEFEED_HOSTS["production"])
  end

  def create
    attributes = access_token_params.merge(user: Current.user)
    @access_token = AccessToken.build_with_token(attributes)

    if @access_token.save
      @access_token.validate_token_async
      redirect_to access_tokens_path, notice: "Access token '#{@access_token.name}' created successfully."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @access_token = find_access_token
  end

  def update
    @access_token = find_access_token
    if @access_token.update(access_token_params.merge(encrypted_token: access_token_params[:token]))
      @access_token.validate_token_async
      redirect_to access_tokens_path, notice: "Access token '#{@access_token.name}' has been updated successfully."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    access_token = access_tokens.find(params[:id])
    access_token.destroy!
    redirect_to access_tokens_path, notice: "Access token '#{access_token.name}' has been deleted."
  end

  private

  def find_access_token
    access_tokens.find(params[:id])
  end

  def access_tokens
    Current.user.access_tokens
  end

  def ordered_access_tokens
    access_tokens.order(created_at: :desc)
  end

  def access_token_params
    params.require(:access_token).permit(:name, :token, :host)
  end
end
