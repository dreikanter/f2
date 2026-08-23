class AccessTokenValidationService
  attr_reader :access_token

  def initialize(access_token)
    @access_token = access_token
  end

  def call
    access_token.begin_validation! unless access_token.validating?

    # Scopes come first because that route is always allowed. It answers for any
    # live token, and tells us whether the rest of the sequence can succeed.
    scopes = fetch_scopes
    return disable_for_missing_scope(scopes) unless scopes_cover_validation?(scopes)

    user_info = fetch_user_info
    managed_groups = fetch_managed_groups

    access_token.with_lock do
      access_token.update!(
        status: :active,
        owner: user_info[:username],
        freefeed_user_id: user_info[:id],
        scopes: scopes,
        last_used_at: Time.current,
        validation_started_at: nil
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
    # The token is dead, not under-permissioned. The scope check above already
    # routed that case elsewhere.
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

  # whoami and managedGroups both sit behind read-my-info. Without it they can
  # only be refused, so there is nothing to learn from asking.
  def scopes_cover_validation?(scopes)
    scopes.include?(AccessToken::READ_MY_INFO_SCOPE)
  end

  # Persist the scopes on the way down. They are what lets the token page say
  # the token is alive but unusable, instead of calling it expired.
  def disable_for_missing_scope(scopes)
    access_token.update!(scopes: scopes)
    access_token.disable_token_and_feeds(event_type: "access_token_missing_scope")
  end

  def fetch_user_info
    freefeed_client.whoami
  end

  def fetch_managed_groups
    freefeed_client.managed_groups
  end

  # Errors are left to #call. A failure here means we don't know what the token
  # can do, and guessing would either gate a capable token or clear the gate for
  # one that can't. The route needs no scopes, so a 401 means the token is dead
  # rather than under-permissioned, and anything else is transient: validation
  # stays unfinished and the job retries.
  #
  # A session token has no scope list to report, and FreeFeed rejects it on this
  # app-token-only route. It is unrestricted, so it gets everything Feeder asks
  # for. Widening TOKEN_SCOPES later means re-reading these tokens.
  def fetch_scopes
    freefeed_client.app_token_info&.fetch(:scopes) || AccessToken::TOKEN_SCOPES
  end
end
