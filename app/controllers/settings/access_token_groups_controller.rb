class Settings::AccessTokenGroupsController < ApplicationController
  def index
    @access_token = Current.user.access_tokens.find(params[:access_token_id])
    @managed_groups = load_managed_groups
    @selected_group = params[:selected_group]

    # TBD: Decouple this controller from settings, make it reusable in admin panel
    @scope = params[:scope] || "feed"
  end

  rescue_from FreefeedClient::Error, with: :handle_freefeed_error

  private

  def freefeed_client
    @freefeed_client ||= FreefeedClient.new(
      host: @access_token.host,
      token: @access_token.token_value
    )
  end

  def load_managed_groups
    freefeed_client.managed_groups
  end

  def handle_freefeed_error(exception)
    render turbo_stream: turbo_stream.replace("groups-select", partial: "settings/access_token_groups/error", locals: { error: exception.message })
  end
end
