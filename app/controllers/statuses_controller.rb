class StatusesController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :require_authentication
  before_action :set_access_token

  def create
    @access_token.validate_token_async

    render turbo_stream: build_turbo_stream_update(access_token: @access_token)
  end

  def show
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

  def set_access_token
    @access_token = access_tokens.find(params[:access_token_id])
  end

  def access_tokens
    Current.user.access_tokens
  end
end
