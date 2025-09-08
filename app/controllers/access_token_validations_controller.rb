class AccessTokenValidationsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :require_authentication

  def create
    @access_token = access_tokens.find(access_token_id)
    @access_token.validate_token_async

    render_status_update(start_polling: true)
  end


  private

  def access_tokens
    Current.user.access_tokens
  end

  def access_token_id
    params[:access_token_id]
  end

  def render_status_update(**locals)
    render turbo_stream: turbo_stream.update(
      dom_id(@access_token, :status),
      partial: "access_tokens/status",
      locals: { token: @access_token, **locals }
    )
  end
end
