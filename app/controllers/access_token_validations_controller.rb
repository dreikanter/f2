class AccessTokenValidationsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :require_authentication

  def show
    @access_token = access_tokens.find(params[:access_token_id])

    render turbo_stream: turbo_stream.update(
      dom_id(@access_token, :status),
      partial: "access_tokens/status",
      locals: { token: @access_token }
    )
  end

  private

  def access_tokens
    Current.user.access_tokens
  end
end
