class Settings::AccessTokensController < ApplicationController
  layout "tailwind"

  def index
    authorize AccessToken
    @access_tokens = policy_scope(AccessToken).order(created_at: :desc)
  end

  def new
    @access_token = AccessToken.new(host: AccessToken::FREEFEED_HOSTS["production"])
    authorize @access_token
  end

  def create
    attributes = access_token_params.merge(user: Current.user)
    @access_token = AccessToken.build_with_token(attributes)
    authorize @access_token

    if @access_token.save
      @access_token.validate_token_async

      # TBD: Perform validation in the token form to ensure the user is adding a valid token
      # TBD: Only the redirect path should depend on user's state
      if Current.user.onboarding?
        redirect_to status_path, notice: "Access token '#{@access_token.name}' created successfully."
      else
        redirect_to settings_access_tokens_path, notice: "Access token '#{@access_token.name}' created successfully."
      end
    else
      render :new, status: :unprocessable_content
    end
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
