# Refetches the FreeFeed groups a token can post to, on user request, without
# touching the token's status (unlike full revalidation, which would briefly
# make publishing reject queued posts). Settles the detail's refresh marker so
# the pages polling for the outcome can stop.
class TokenGroupsRefreshJob < ApplicationJob
  include RateLimited

  queue_as :default

  # refresh_id ties this run to the marker begin_groups_refresh! created, so a
  # long-delayed run can't settle a newer refresh started after its marker went
  # stale.
  def perform(access_token, refresh_id)
    detail = access_token.access_token_detail
    return if detail.nil?
    return detail.fail_groups_refresh!(refresh_id) unless access_token.active?

    result = RateLimit.acquire(:freefeed, subject: access_token.rate_limit_subject, cost: { get: 1 })
    return reschedule_for_rate_limit(result.retry_after) unless result.allowed?

    groups = access_token.build_client.managed_groups
    detail.complete_groups_refresh!(groups, refresh_id)
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
    detail.fail_groups_refresh!(refresh_id)
  rescue StandardError => e
    Rails.error.report(e, context: { access_token_id: access_token.id })
    detail.fail_groups_refresh!(refresh_id)
  end

  private

  # Leave a settled marker behind when throttle retries run out, so polling
  # pages and future refreshes don't see a refresh that will never finish.
  def on_rate_limit_exhausted(_error)
    access_token, refresh_id = arguments
    access_token.access_token_detail&.fail_groups_refresh!(refresh_id)
  end
end
