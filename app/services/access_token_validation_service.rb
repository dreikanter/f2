class AccessTokenValidationService
  attr_reader :access_token

  def initialize(access_token)
    @access_token = access_token
  end

  def call
    access_token.validating! unless access_token.validating?
    user_info = fetch_user_info
    managed_groups = fetch_managed_groups

    access_token.with_lock do
      access_token.update!(
        status: :active,
        owner: user_info[:username],
        freefeed_user_id: user_info[:id],
        last_used_at: Time.current
      )

      access_token_detail = access_token.access_token_detail || access_token.build_access_token_detail

      access_token_detail.update!(
        data: {
          user_info: user_info,
          managed_groups: managed_groups
        }
      )
    end

    broadcast_resolution
  rescue FreefeedClient::UnauthorizedError
    access_token.disable_token_and_feeds
    broadcast_resolution
  rescue RateLimit::Throttled
    # Throttling is control flow, not a validation failure: let it propagate so
    # the job reschedules. Reporting it here would surface a fault on every
    # deferred run.
    raise
  rescue StandardError => e
    Rails.error.report(e, context: { access_token_id: access_token.id })
    raise
  end

  private

  # Tell the token's show page (subscribed via turbo_stream_from) to refresh
  # now that validation has resolved to active or inactive.
  def broadcast_resolution
    access_token.broadcast_refresh
  end

  def freefeed_client
    @freefeed_client ||= access_token.build_client
  end

  def fetch_user_info
    freefeed_client.whoami
  end

  def fetch_managed_groups
    freefeed_client.managed_groups
  end
end
