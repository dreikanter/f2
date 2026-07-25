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
  end
end
