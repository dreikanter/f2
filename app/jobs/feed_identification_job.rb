class FeedIdentificationJob < ApplicationJob
  queue_as :default

  def perform(user_id, input)
    user = User.find_by(id: user_id)

    unless user
      Rails.logger.warn("FeedIdentificationJob skipped: User #{user_id} not found (job_id: #{job_id}, input: #{input})")
      return
    end

    FeedIdentificationFetcher.new(user: user, input: input).identify
  end
end
