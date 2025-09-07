class TokenValidationsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :require_authentication

  def create
    @access_token = access_tokens.find(access_token_id)
    @access_token.validate_token_async

    render turbo_stream: turbo_stream.update(
      dom_id(@access_token, :status),
      partial: "access_tokens/status",
      locals: { token: @access_token, validating: true }
    )
  end

  private

  def access_tokens
    Current.user.access_tokens
  end

  def access_token_id
    params[:access_token_id]
  end
end
