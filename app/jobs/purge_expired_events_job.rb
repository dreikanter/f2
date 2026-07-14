# Deletes expired events: those whose explicit expiration has passed, plus
# events with no explicit expiration once they age past Event::DEFAULT_RETENTION.
#
# This job intentionally deletes in small batches so a daily cron run does not
# hold locks on the events table for one long operation.
class PurgeExpiredEventsJob < ApplicationJob
  include RecordsJobRun

  queue_as :default

  BATCH_SIZE = 500
  BATCH_PAUSE = 0.01.seconds

  def perform
    deleted_count = 0

    Event.expired.in_batches(of: BATCH_SIZE) do |events|
      EventReference.where(event_id: events.select(:id)).delete_all
      # Events can also BE references (feed_refresh → web_search); purging
      # the target must clear those inbound rows too or they dangle.
      EventReference.where(reference_type: "Event", reference_id: events.select(:id)).delete_all
      deleted_count += events.delete_all
      sleep BATCH_PAUSE
    end

    record_event(type: "job.purge_expired_events.completed",
                 message: "Purged #{deleted_count} expired events",
                 deleted_count: deleted_count)

    deleted_count
  end
end
