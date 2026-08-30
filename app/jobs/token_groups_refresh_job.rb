# Refetches the FreeFeed groups a token can post to, on user request, without
# touching the token's state (unlike full revalidation, which would briefly
# make publishing reject queued posts). Settles the detail's refresh marker so
# the pages polling for the outcome can stop.
class TokenGroupsRefreshJob < ApplicationJob
  include RateLimited

  queue_as :default

  # @param run [OperationRun] groups refresh being performed
  def perform(run)
    return unless run.running?

    detail = run.subject
    access_token = detail.access_token
    return run.fail! unless access_token.active?

    result = RateLimit.acquire(:freefeed, subject: access_token.rate_limit_subject, cost: { get: 1 })
    return reschedule_for_rate_limit(result.retry_after) unless result.allowed?

    groups = access_token.build_client.managed_groups
    return unless run.succeed! { |current_detail| current_detail.replace_managed_groups!(groups) }

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
    access_token.enqueue_validation
    run.fail!
  rescue StandardError => e
    Rails.error.report(e, context: { access_token_id: access_token.id })
    run.fail!
  end

  private

  # Leave a settled marker behind when throttle retries run out, so polling
  # pages and future refreshes don't see a refresh that will never finish.
  def on_rate_limit_exhausted(_error)
    arguments.first.fail!
  end
end
