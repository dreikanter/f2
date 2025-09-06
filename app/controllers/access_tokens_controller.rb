class AccessTokensController < ApplicationController
  before_action :require_authentication

  def index
    @access_tokens = ordered_access_tokens
    @new_access_token = AccessToken.new
  end

  def create
    access_token = access_tokens.build(access_token_params)

    if access_token.save
      redirect_to access_tokens_path, notice: "Access token '#{access_token.name}' created successfully."
    else
      @access_tokens = ordered_access_tokens
      @new_access_token = access_token
      render :index, status: :unprocessable_content
    end
  end

  def destroy
    access_token = access_tokens.find(params[:id])
    access_token.destroy!
    redirect_to access_tokens_path, notice: "Access token '#{access_token.name}' has been deleted."
  end

  private

  def access_tokens
    Current.user.access_tokens
  end

  def ordered_access_tokens
    access_tokens.order(created_at: :desc)
  end

  def access_token_params
    params.require(:access_token).permit(:name, :token)
  end
end
