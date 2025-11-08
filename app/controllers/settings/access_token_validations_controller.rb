class Settings::AccessTokenValidationsController < ApplicationController
  def show
    @access_token = find_access_token
    authorize @access_token, policy_class: AccessTokenPolicy

    render formats: [:turbo_stream]
  end

  private

  def find_access_token
    policy_scope(AccessToken).find(params[:access_token_id])
  end
end
