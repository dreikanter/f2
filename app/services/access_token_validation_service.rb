class AccessTokenValidationService
  attr_reader :access_token

  def initialize(access_token)
    @access_token = access_token
  end

  def call
    user_info = freefeed_client.whoami

    ActiveRecord::Base.transaction do
      updates = {
        status: :active,
        owner: user_info[:username],
        last_used_at: Time.current
      }

      # Set name if it's blank
      if access_token.name.blank?
        updates[:name] = "#{user_info[:username]}@#{access_token.host_domain}"
      end

      access_token.update!(updates)
    end

    # Cache token details - failures here should not deactivate the token
    begin
      managed_groups = fetch_managed_groups
      cache_token_details(user_info, managed_groups)
    rescue => e
      Rails.logger.error("Failed to cache token details for access_token #{access_token.id}: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
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

  def fetch_managed_groups
    freefeed_client.managed_groups
  rescue
    # Managed groups are optional metadata - return empty array on failure
    []
  end

  def cache_token_details(user_info, managed_groups)
    details_data = {
      user_info: user_info,
      managed_groups: managed_groups,
      cached_at: Time.current.iso8601
    }

    access_token_detail = access_token.access_token_detail || access_token.build_access_token_detail
    access_token_detail.update!(
      data: details_data,
      expires_at: AccessTokenDetail::TTL.from_now
    )
  rescue ActiveRecord::RecordNotUnique
    # Another job created the detail concurrently, reload and update
    access_token.reload
    access_token.access_token_detail.update!(
      data: details_data,
      expires_at: AccessTokenDetail::TTL.from_now
    )
  end

  def disable_token_and_feeds
    access_token.update_columns(status: :inactive, updated_at: Time.current)
    access_token.feeds.enabled.update_all(state: :disabled)
  end
end
