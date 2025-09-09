class AccessTokenValidationsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :require_authentication

  def create
    @access_token = access_tokens.find(access_token_id)
    @access_token.validate_token_async

    render turbo_stream: build_turbo_stream_update(access_token: @access_token)
  end

  def show
    @access_token = access_tokens.find(params[:id])

    render turbo_stream: build_turbo_stream_update(access_token: @access_token)
  end

  private

  def build_turbo_stream_update(locals)
    turbo_stream.update(
      dom_id(@access_token, :status),
      partial: "shared/access_token_status",
      locals: locals
    )
  end

  def access_tokens
    Current.user.access_tokens
  end

  def access_token_id
    params[:access_token_id]
  end
end
