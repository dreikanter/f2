class AccessTokenGroupsController < ApplicationController
  before_action :load_access_token

  def index
    # Turbo Stream response handled by view template
  rescue FreefeedClient::Error => e
    render turbo_stream: turbo_stream.replace("group-select-wrapper", partial: "access_token_groups/error", locals: { error: e.message })
  end

  private

  def load_access_token
    @access_token = Current.user.access_tokens.find(params[:access_token_id])
  end

  def freefeed_client
    @freefeed_client ||= FreefeedClient.new(
      host: @access_token.host,
      token: @access_token.token_value
    )
  end

  def managed_groups
    @managed_groups ||= freefeed_client.managed_groups
  end
end
