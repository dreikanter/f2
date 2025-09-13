class AccessTokenGroupsController < ApplicationController
  before_action :load_access_token

  def index
    client = FreefeedClient.new(
      host: @access_token.host,
      token: @access_token.token_value
    )

    groups = client.managed_groups
    render json: {
      groups: groups.map { |group|
        {
          id: group[:id],
          username: group[:username],
          screen_name: group[:screen_name],
          is_private: group[:is_private],
          is_restricted: group[:is_restricted]
        }
      }
    }
  rescue FreefeedClient::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def load_access_token
    @access_token = Current.user.access_tokens.find(params[:access_token_id])
  end
end
