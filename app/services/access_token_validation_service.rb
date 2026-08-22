class AccessTokenValidationService
  attr_reader :access_token

  def initialize(access_token)
    @access_token = access_token
  end

  def call
    access_token.validating! unless access_token.validating?
    user_info = fetch_user_info
    managed_groups = fetch_managed_groups
    scopes = fetch_scopes

    access_token.with_lock do
      access_token.update!(
        status: :active,
        owner: user_info[:username],
        freefeed_user_id: user_info[:id],
        scopes: scopes,
        last_used_at: Time.current
      )

      access_token_detail = access_token.access_token_detail || access_token.build_access_token_detail

      # Also settles any in-flight groups refresh: validation just wrote a
      # fresh list, so pages polling for a refresh outcome can stop.
      access_token_detail.update!(
        freefeed_user_info: user_info.deep_stringify_keys,
        managed_groups: managed_groups.map { |group| group.deep_stringify_keys },
        groups_refresh_state: nil,
        groups_refresh_requested_at: nil
      )
    end
  rescue FreefeedClient::UnauthorizedError, FreefeedClient::ForbiddenError
    # A 401/403 on whoami or managedGroups means the token can't even read its
    # own account, so it's effectively dead — disable it and its feeds.
    access_token.disable_token_and_feeds
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

  def freefeed_client
    @freefeed_client ||= access_token.build_client
  end

  def fetch_user_info
    freefeed_client.whoami
  end

  def fetch_managed_groups
    freefeed_client.managed_groups
  end

  # Scopes only gate optional calls, never publishing, so a failure here must
  # not sink an otherwise good validation. Falling back to nil re-opens the
  # gate: callers attempt the call and handle the rejection, which beats
  # gating on a stale list after the token secret was swapped for a new one.
  def fetch_scopes
    freefeed_client.app_token_info&.fetch(:scopes)
  rescue FreefeedClient::InvalidTokenError
    # The one 401 that isn't a scope-lookup failure: FreeFeed raises this only
    # for "inactive or expired token", so let it reach the handler that disables
    # the token. A token merely lacking the scope answers 401 too, but as a
    # plain UnauthorizedError — swallowed below, or it would take down every
    # feed on a token that publishes perfectly well.
    raise
  rescue FreefeedClient::Error => e
    Rails.error.report(e, context: { access_token_id: access_token.id })
    nil
  end
end
