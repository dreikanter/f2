class PruneFeedIdentificationsJob < ApplicationJob
  queue_as :default

  def perform
    FeedIdentification.obsolete.in_batches(of: 500).delete_all
  end
end
