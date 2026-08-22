class UpdateFeedSubscribersCountsJob < ApplicationJob
  queue_as :default

  def perform
    # Feeds on a token without read-users-info are left out: the per-feed job
    # would only skip them, so enqueuing is pure overhead.
    Feed.enabled
        .where.not(target_group: [nil, ""])
        .where(access_token: AccessToken.allowing_scope(AccessToken::READ_USERS_INFO_SCOPE))
        .find_each do |feed|
      UpdateFeedSubscribersCountJob.perform_later(feed)
    end
  end
end
