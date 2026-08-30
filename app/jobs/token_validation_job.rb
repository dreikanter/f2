class TokenValidationJob < ApplicationJob
  include RateLimited

  queue_as :default

  # @param access_token [AccessToken] token being validated
  # @param run_id [String] validation UUID
  def perform(access_token, run_id)
    return unless access_token.claim_validation!(run_id)

    # Validation makes up to three GETs: the token's scopes, then whoami and
    # managedGroups when the scopes allow them.
    result = RateLimit.acquire(:freefeed, subject: access_token.rate_limit_subject, cost: { get: 3 })
    return reschedule_for_rate_limit(result.retry_after) unless result.allowed?

    AccessTokenValidationService.new(access_token, run_id: run_id).call
  rescue RateLimit::Throttled => e
    reschedule_for_rate_limit(e.retry_after)
  end

  private

  # Validation flips the token to `validating` before enqueuing. If we exhaust
  # the throttle retries, reset it to `pending` so it doesn't stay stuck — the
  # recurring schedulers can pick it up again later.
  def on_rate_limit_exhausted(_error)
    access_token, run_id = arguments
    AccessToken.where(id: access_token.id, validation_run_id: run_id)
               .update_all(status: AccessToken.statuses[:pending], updated_at: Time.current)
  end
end
