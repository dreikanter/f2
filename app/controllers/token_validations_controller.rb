class TokenValidationsController < ApplicationController
  before_action :require_authentication

  def create
    @access_token = access_tokens.find(params[:access_token_id])
    @access_token.validate_token_async

    render turbo_stream: turbo_stream.update(
      "access_token_#{@access_token.id}_status",
      partial: "access_tokens/status",
      locals: { token: @access_token, validating: true }
    )
  end

  private

  def access_tokens
    Current.user.access_tokens
  end
end
