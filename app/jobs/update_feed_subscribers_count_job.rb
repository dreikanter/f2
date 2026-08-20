class UpdateFeedSubscribersCountJob < ApplicationJob
  include RateLimited

  queue_as :default

  def perform(feed)
    return unless feed.enabled? && feed.access_token&.active? && feed.target_group.present?

    result = RateLimit.acquire(:freefeed, subject: feed.access_token.rate_limit_subject, cost: { get: 1 })
    return reschedule_for_rate_limit(result.retry_after) unless result.allowed?

    count = feed.access_token.build_client.subscribers_count(feed.target_group)
    feed.update!(subscribers_count: count, subscribers_count_updated_at: Time.current)
  rescue RateLimit::Throttled => e
    reschedule_for_rate_limit(e.retry_after)
  rescue FreefeedClient::InvalidTokenError
    # A dead token can't publish either, and a dormant feed may never reach the
    # publishing flow that would notice — send the token through validation,
    # which owns disabling it and notifying the user.
    feed.access_token.validate_token_async
  rescue FreefeedClient::UnauthorizedError, FreefeedClient::ForbiddenError, FreefeedClient::NotFoundError => e
    # Statistics can be out of a token's reach while publishing still works:
    # scoped app tokens get 401 "token has no access to this API method", and a
    # renamed or deleted group 404s. Expected external conditions — keep the
    # stale count and leave token/feed fallout to the flows that own it.
    Rails.logger.info("Skipping subscribers count for feed #{feed.id}: #{e.message}")
  end
end
