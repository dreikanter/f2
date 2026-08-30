class TokenValidationJob < ApplicationJob
  include RateLimited

  queue_as :default

  # @param access_token_id [String, AccessToken] token UUID or a deferred check's record
  # @param run_id [String, nil] validation UUID
  def perform(access_token_id, run_id = nil)
    access_token = access_token_id.is_a?(AccessToken) ? access_token_id : AccessToken.find_by(id: access_token_id)
    return unless access_token

    deferred = run_id.nil?
    run_id ||= SecureRandom.uuid
    return unless access_token.claim_validation!(run_id, start_if_idle: deferred)

    # RateLimited#retry_job serializes this job's arguments. Add the run ID for
    # deferred one-argument checks so a retry keeps ownership of the same run.
    arguments.replace([access_token.id, run_id])

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
    access_token_id, run_id = arguments
    AccessToken.where(id: access_token_id, validation_run_id: run_id)
               .update_all(status: AccessToken.statuses[:pending], updated_at: Time.current)
  end
end
