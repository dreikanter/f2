class Settings::AccessTokensController < ApplicationController
  def index
    authorize AccessToken
    @access_tokens = policy_scope(AccessToken).order(created_at: :desc)
  end

  def edit
    @access_token = find_access_token
    authorize @access_token
  end

  def update
    @access_token = find_access_token
    authorize @access_token

    update_params = access_token_params
    token = update_params.delete(:token)
    update_params[:encrypted_token] = token if token.present?

    if @access_token.update(update_params)
      @access_token.validate_token_async if token.present?
      redirect_to settings_access_tokens_path, notice: "Access token '#{@access_token.name}' has been updated successfully."
    else
      render :edit, status: :unprocessable_content
    end
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
end
