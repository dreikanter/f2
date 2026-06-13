class AccessTokens::ValidationsController < ApplicationController
  def show
    access_token = find_access_token
    authorize access_token, policy_class: AccessTokenPolicy

    # Stay silent while validation is still in flight so the poller leaves the
    # spinner running instead of redrawing (and restarting) it every cycle.
    return head :no_content if access_token.pending? || access_token.validating?

    render turbo_stream: turbo_stream.update(
      "access-token-show",
      partial: "access_tokens/show_content",
      locals: { access_token: access_token, feed_id: params[:feed_id] }
    )
  end

  private

  def find_access_token
    policy_scope(AccessToken).find(params[:access_token_id])
  end
end
