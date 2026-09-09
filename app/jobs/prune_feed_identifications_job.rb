class PruneFeedIdentificationsJob < ApplicationJob
  queue_as :default

  RETENTION = 7.days

  def perform
    obsolete = FeedIdentification.where(configuration_digest: nil)
                                 .or(FeedIdentification.where.not(configuration_digest: FeedProfile.configuration_digest))
                                 .or(FeedIdentification.where(updated_at: ..RETENTION.ago))
    obsolete.in_batches(of: 500).delete_all
  end
end
