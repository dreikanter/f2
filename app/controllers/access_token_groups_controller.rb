class AccessTokenGroupsController < ApplicationController
  def index
    @access_token = Current.user.access_tokens.find(params[:access_token_id])
    @managed_groups = managed_groups
  end

  rescue_from FreefeedClient::Error, with: :handle_freefeed_error

  private

  def freefeed_client
    @freefeed_client ||= FreefeedClient.new(
      host: @access_token.host,
      token: @access_token.token_value
    )
  end

  def managed_groups
    @managed_groups ||= freefeed_client.managed_groups
  end

  def handle_freefeed_error(exception)
    render turbo_stream: turbo_stream.replace("groups-select", partial: "access_token_groups/error", locals: { error: exception.message })
  end
end
