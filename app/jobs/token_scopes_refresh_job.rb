# Records what a token is allowed to do when Feeder has never read it: tokens
# validated before scopes were recorded carry an empty set, which the gates
# reading them can't tell from "not allowed". Reads the scopes without touching
# the token's status, unlike full revalidation, which would briefly make
# publishing reject queued posts.
class TokenScopesRefreshJob < ApplicationJob
  include RateLimited

  queue_as :default

  def perform(access_token)
    # FreeFeed fixes an app token's scopes when it issues the token, so once
    # they are on record there is nothing left to re-read.
    return if access_token.scopes_recorded? || !access_token.active?

    result = RateLimit.acquire(:freefeed, subject: access_token.rate_limit_subject, cost: { get: 1 })
    return reschedule_for_rate_limit(result.retry_after) unless result.allowed?

    access_token.update!(scopes: access_token.remote_scopes)
  rescue RateLimit::Throttled => e
    reschedule_for_rate_limit(e.retry_after)
  rescue FreefeedClient::UnauthorizedError
    # The route needs no scopes of its own, so a refusal means the token is
    # dead rather than under-permissioned. Validation owns disabling it and
    # notifying the user.
    TokenValidationJob.perform_later(access_token)
  end
end
