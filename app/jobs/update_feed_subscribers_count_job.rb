class UpdateFeedSubscribersCountJob < ApplicationJob
  include RateLimited

  queue_as :default

  def perform(feed)
    return unless feed.enabled? && feed.access_token&.active? && feed.target_group.present?

    # Statistics sit behind read-users-info, and a token can never gain a scope
    # it wasn't issued with. Without it the request can only ever be refused, so
    # skip before spending any rate-limit budget on it.
    return unless feed.access_token.allows_scope?(AccessToken::READ_USERS_INFO_SCOPE)

    result = RateLimit.acquire(:freefeed, subject: feed.access_token.rate_limit_subject, cost: { get: 1 })
    return reschedule_for_rate_limit(result.retry_after) unless result.allowed?

    count = feed.access_token.build_client.subscribers_count(feed.target_group)
    feed.update!(subscribers_count: count, subscribers_count_updated_at: Time.current)
  rescue RateLimit::Throttled => e
    reschedule_for_rate_limit(e.retry_after)
  rescue FreefeedClient::InvalidTokenError
    # A dead token can't publish either, and a dormant feed may never reach the
    # publishing flow that would notice — enqueue validation, which owns
    # disabling the token and notifying the user. Not validate_token_async: its
    # eager flip to `validating` would make FreefeedPublisher reject queued
    # posts as poison while the validation job waits to run.
    feed.access_token.enqueue_validation
  rescue FreefeedClient::UnauthorizedError, FreefeedClient::ForbiddenError, FreefeedClient::NotFoundError => e
    # Statistics can be out of a token's reach while publishing still works:
    # scoped app tokens get 401 "token has no access to this API method", and a
    # renamed or deleted group 404s. Expected external conditions — keep the
    # stale count and leave token/feed fallout to the flows that own it.
    Rails.logger.info("Skipping subscribers count for feed #{feed.id}: #{e.message}")
  end
end
