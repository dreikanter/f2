class AccessTokenValidationService
  attr_reader :access_token

  def initialize(access_token)
    @access_token = access_token
  end

  def call
    access_token.update!(
      status: :active,
      owner: user_info[:username],
      last_used_at: Time.current
    )

    cache_token_details
  rescue StandardError => e
    # TBD: Use more robust approach to handle errorhere
    disable_token_and_feeds
  end

  private

  def freefeed_client
    @freefeed_client ||= FreefeedClient.new(
      host: access_token.host,
      token: access_token.token_value
    )
  end

  def cache_token_details
    access_token.with_lock do
      access_token_detail = access_token.access_token_detail || access_token.build_access_token_detail

      access_token_detail.update!(
        data: {
          user_info: user_info,
          managed_groups: managed_groups
        }
      )
    end
  end

  def disable_token_and_feeds
    access_token.update_columns(status: :inactive, updated_at: Time.current)
    access_token.feeds.enabled.update_all(state: :disabled)
  end

  def user_info
    @user_info ||= freefeed_client.whoami
  end

  def managed_groups
    @managed_groups ||= freefeed_client.managed_groups
  end
end
