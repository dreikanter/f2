class TokenValidationsController < ApplicationController
  before_action :require_authentication

  def create
    @access_token = access_tokens.find(params[:access_token_id])

    # Queue the validation job
    @access_token.validate_token_async

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "access_token_#{@access_token.id}_status",
          partial: "access_tokens/status",
          locals: { token: @access_token, validating: true }
        )
      end
      format.html { redirect_to access_tokens_path }
    end
  end

  private

  def access_tokens
    Current.user.access_tokens
  end
end
