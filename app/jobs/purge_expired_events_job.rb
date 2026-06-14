# Deletes events whose expiration time has passed, plus events with no explicit
# expiration once they are older than DEFAULT_RETENTION.
#
# This job intentionally deletes in small batches so a daily cron run does not
# hold locks on the events table for one long operation.
class PurgeExpiredEventsJob < ApplicationJob
  queue_as :default

  DEFAULT_RETENTION = 1.month
  BATCH_SIZE = 500
  BATCH_PAUSE = 0.01.seconds

  def perform
    deleted_count = 0

    Event.purgeable(DEFAULT_RETENTION).in_batches(of: BATCH_SIZE) do |events|
      EventReference.where(event_id: events.select(:id)).delete_all
      deleted_count += events.delete_all
      sleep BATCH_PAUSE
    end

    deleted_count
  end
end
