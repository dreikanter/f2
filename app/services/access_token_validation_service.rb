class AccessTokenValidationService
  attr_reader :access_token

  def initialize(access_token)
    @access_token = access_token
  end

  def call
    user_info = freefeed_client.whoami
    managed_groups = freefeed_client.managed_groups

    ActiveRecord::Base.transaction do
      updates = {
        status: :active,
        owner: user_info[:username],
        last_used_at: Time.current
      }

      # Update name if it's the default name
      if access_token.name.start_with?("New token for")
        updates[:name] = "#{user_info[:username]} at #{access_token.host_domain}"
      end

      access_token.update!(updates)

      cache_token_details(user_info, managed_groups)
    end
  rescue
    ActiveRecord::Base.transaction do
      disable_token_and_feeds
    end
  end

  private

  def freefeed_client
    @freefeed_client ||= FreefeedClient.new(
      host: access_token.host,
      token: access_token.token_value
    )
  end

  def cache_token_details(user_info, managed_groups)
    details_data = {
      user_info: user_info,
      managed_groups: managed_groups,
      cached_at: Time.current.iso8601
    }

    if access_token.access_token_detail
      access_token.access_token_detail.update!(
        data: details_data,
        expires_at: AccessTokenDetail::TTL.from_now
      )
    else
      access_token.create_access_token_detail!(
        data: details_data,
        expires_at: AccessTokenDetail::TTL.from_now
      )
    end
  end

  def disable_token_and_feeds
    access_token.update!(status: :inactive)
    access_token.feeds.enabled.update_all(state: :disabled)
  end
end
