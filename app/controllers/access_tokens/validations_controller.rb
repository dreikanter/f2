class AccessTokens::ValidationsController < ApplicationController
  def show
    access_token = find_access_token
    authorize access_token, policy_class: AccessTokenPolicy

    render turbo_stream: turbo_stream.update(
      "access-token-show",
      partial: "access_tokens/show_content",
      locals: { access_token: access_token }
    )
  end

  private

  def find_access_token
    policy_scope(AccessToken).find(params[:access_token_id])
  end
end
