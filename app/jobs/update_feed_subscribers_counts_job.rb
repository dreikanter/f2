class UpdateFeedSubscribersCountsJob < ApplicationJob
  queue_as :default

  def perform
    Feed.enabled.where.not(access_token_id: nil).where.not(target_group: [nil, ""]).find_each do |feed|
      UpdateFeedSubscribersCountJob.perform_later(feed)
    end
  end
end
