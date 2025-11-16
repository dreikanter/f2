class FeedDetailsJob < ApplicationJob
  queue_as :default

  def perform(user_id, url)
    user = User.find_by(id: user_id)

    unless user
      Rails.logger.warn("FeedDetailsJob skipped: User #{user_id} not found (job_id: #{job_id}, url: #{url})")
      return
    end

    FeedDetails.new(user: user, url: url).identify
  end
end
