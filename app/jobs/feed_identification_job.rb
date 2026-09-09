class FeedIdentificationJob < ApplicationJob
  queue_as :default

  # @param feed_identification_id [String] UUID of the FeedIdentification
  # @param run_id [String] run token captured when the job was enqueued
  # @param configuration_digest [String] expected registry; defaults for previously queued jobs
  def perform(feed_identification_id, run_id, configuration_digest = FeedProfile.configuration_digest)
    return unless configuration_digest == FeedProfile.configuration_digest

    identification = FeedIdentification.find_by(id: feed_identification_id, status: :processing, run_id: run_id,
                                                configuration_digest: configuration_digest)
    return unless identification

    FeedIdentificationFetcher.new(feed_identification: identification, run_id: run_id).identify
  end
end
