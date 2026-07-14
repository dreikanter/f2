# Event-backed accounting for web-search API calls.
class WebSearchUsage
  EVENT_TYPE = "web_search".freeze
  STATS_PERIOD = 30.days
  PERIODS = {
    day: 1.day,
    week: 1.week,
    month: STATS_PERIOD
  }.freeze

  class << self
    def record!(credential:, refresh_event: nil)
      event = Event.create!(
        type: EVENT_TYPE,
        level: :debug,
        subject: credential,
        user: credential.user,
        metadata: { provider: credential.provider }
      )
      refresh_event&.event_references&.create!(reference: event)
      event
    end

    def for_credential(credential, since: nil)
      scope = Event.where(type: EVENT_TYPE, subject: credential)
      since ? scope.where(created_at: since..) : scope
    end

    def referenced_by(event)
      Event.where(
        type: EVENT_TYPE,
        id: event.event_references.where(reference_type: "Event").select(:reference_id)
      ).order(:created_at)
    end

    def for_feed(feed, since: STATS_PERIOD.ago)
      refresh_event_ids = Event.where(
        type: "feed_refresh",
        subject: feed,
        created_at: since..
      ).select(:id)

      Event.where(
        type: EVENT_TYPE,
        id: EventReference.where(event_id: refresh_event_ids, reference_type: "Event").select(:reference_id)
      )
    end

    def counts_for_periods(credential, now: Time.current)
      PERIODS.transform_values do |period|
        for_credential(credential, since: now - period).where(created_at: ..now).count
      end
    end

    def estimated_cost_cents(events)
      counts = events.group_by { |event| event.metadata.fetch("provider") }.transform_values(&:size)
      counts.sum(BigDecimal("0")) do |provider, count|
        BigDecimal(WebSearchProvider.cents_per_1k_requests_for(provider).to_s) * count / 1000
      end
    end
  end
end
