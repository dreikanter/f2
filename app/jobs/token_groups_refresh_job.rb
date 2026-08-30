# Refetches the FreeFeed groups a token can post to, on user request, without
# touching the token's status (unlike full revalidation, which would briefly
# make publishing reject queued posts). Settles the detail's refresh marker so
# the pages polling for the outcome can stop.
class TokenGroupsRefreshJob < ApplicationJob
  include RateLimited

  queue_as :default

  # The optional default lets jobs enqueued by the previous release drain
  # without touching a run they cannot identify.
  def perform(access_token, run_id = nil)
    return if run_id.blank?

    detail = running_detail(access_token, run_id)
    return unless detail&.groups_refresh_running?(run_id: run_id)
    return detail.fail_groups_refresh!(run_id: run_id) unless access_token.active?

    result = RateLimit.acquire(:freefeed, subject: access_token.rate_limit_subject, cost: { get: 1 })
    return reschedule_for_rate_limit(result.retry_after) unless result.allowed?

    groups = access_token.build_client.managed_groups
    return unless detail.complete_groups_refresh!(groups, run_id: run_id)

    Rails.cache.write(
      access_token.groups_cache_key,
      groups.map { |group| group[:username] },
      expires_in: AccessToken::GROUPS_CACHE_TTL
    )
  rescue RateLimit::Throttled => e
    reschedule_for_rate_limit(e.retry_after)
  rescue FreefeedClient::UnauthorizedError, FreefeedClient::ForbiddenError
    # The token can't even read its own groups — hand it to validation, which
    # owns disabling the token and notifying the user.
    TokenValidationJob.perform_later(access_token)
    detail.fail_groups_refresh!(run_id: run_id)
  rescue StandardError => e
    Rails.error.report(e, context: { access_token_id: access_token.id })
    detail.fail_groups_refresh!(run_id: run_id)
  end

  private

  # Leave a settled marker behind when throttle retries run out, so polling
  # pages and future refreshes don't see a refresh that will never finish.
  def on_rate_limit_exhausted(_error)
    access_token, run_id = arguments
    running_detail(access_token, run_id)&.fail_groups_refresh!(run_id: run_id)
  end

  def running_detail(access_token, run_id)
    AccessTokenDetail.find_by(
      access_token_id: access_token.id,
      groups_refresh_state: :running,
      groups_refresh_run_id: run_id
    )
  end
end
