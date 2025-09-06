class AccessTokensController < ApplicationController
  before_action :require_authentication
  before_action :find_access_token, only: :destroy

  def index
    @access_tokens = Current.user.access_tokens.active.order(created_at: :desc)
    @new_access_token = AccessToken.new
  end

  def create
    @access_token = Current.user.access_tokens.build(access_token_params)

    if @access_token.save
      @token_value = @access_token.token
      redirect_to access_tokens_path, notice: "Access token '#{@access_token.name}' created successfully."
    else
      @access_tokens = Current.user.access_tokens.active.order(created_at: :desc)
      @new_access_token = @access_token
      render :index, status: :unprocessable_content
    end
  end

  def destroy
    @access_token.deactivate!
    redirect_to access_tokens_path, notice: "Access token '#{@access_token.name}' has been deactivated."
  end

  private

  def find_access_token
    @access_token = Current.user.access_tokens.find(params[:id])
  end

  def access_token_params
    params.require(:access_token).permit(:name, :token)
  end
end
