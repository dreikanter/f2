class AccessTokenGroupsController < ApplicationController
  before_action :load_access_token

  def index
    respond_to do |format|
      format.turbo_stream
      format.json do
        render json: {
          groups: managed_groups.map { |group|
            {
              id: group[:id],
              username: group[:username],
              screen_name: group[:screen_name],
              is_private: group[:is_private],
              is_restricted: group[:is_restricted]
            }
          }
        }
      end
    end
  rescue FreefeedClient::Error => e
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("group-select-wrapper", partial: "access_token_groups/error", locals: { error: e.message }) }
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
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
