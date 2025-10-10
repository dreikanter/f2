class Settings::AccessTokenGroupsController < ApplicationController
  CACHE_EXPIRY = 10.minutes

  def index
    @access_token = Current.user.access_tokens.find(params[:access_token_id])
    @managed_groups = load_managed_groups
    @selected_group = params[:selected_group]
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
    cache_key = "access_token_#{@access_token.id}_managed_groups"

    # Skip cache if refresh is requested
    if params[:refresh] == "true"
      Rails.cache.delete(cache_key)
    end

    Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRY) do
      groups = freefeed_client.managed_groups
      groups.sort_by { |group| group[:username] }
    end
  end

  def handle_freefeed_error(exception)
    render turbo_stream: turbo_stream.replace("groups-select", partial: "settings/access_token_groups/error", locals: { error: exception.message })
  end
end
