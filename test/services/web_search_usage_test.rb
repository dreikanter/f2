require "test_helper"

class WebSearchUsageTest < ActiveSupport::TestCase
  test ".record! should create a credential event and optional refresh reference" do
    credential = create(:search_credential, :active)
    refresh_event = Event.create!(type: "feed_refresh", level: :info, user: credential.user)

    search_event = WebSearchUsage.record!(credential: credential, refresh_event: refresh_event)

    assert_equal WebSearchUsage::EVENT_TYPE, search_event.type
    assert_equal "debug", search_event.level
    assert_equal credential, search_event.subject
    assert_equal credential.user, search_event.user
    assert_equal credential.provider, search_event.metadata.fetch("provider")
    assert_equal search_event, refresh_event.references.sole
  end

  test ".record! should leave preview and validation searches unreferenced" do
    credential = create(:search_credential, :active)

    search_event = WebSearchUsage.record!(credential: credential)

    assert_empty search_event.incoming_event_references
  end

  test ".counts_for_periods should use bounded day week and month windows" do
    credential = create(:search_credential, :active)
    now = Time.zone.parse("2026-07-14 12:00:00")

    travel_to(now) { WebSearchUsage.record!(credential: credential) }
    travel_to(now - 2.days) { WebSearchUsage.record!(credential: credential) }
    travel_to(now - 8.days) { WebSearchUsage.record!(credential: credential) }
    travel_to(now - 31.days) { WebSearchUsage.record!(credential: credential) }

    assert_equal({ day: 1, week: 2, month: 3 }, WebSearchUsage.counts_for_periods(credential, now: now))
  end

  test ".estimated_cost_cents should preserve fractional cents across providers" do
    user = create(:user)
    credentials = {
      "serper" => create(:search_credential, :active, user: user, provider: "serper", display_name: "Serper"),
      "brave" => create(:search_credential, :active, user: user, provider: "brave", display_name: "Brave"),
      "tavily" => create(:search_credential, :active, user: user, provider: "tavily", display_name: "Tavily")
    }
    events = credentials.map do |provider, credential|
      WebSearchUsage.record!(credential: credential).tap do |event|
        assert_equal provider, event.metadata.fetch("provider")
      end
    end

    assert_equal BigDecimal("1.4"), WebSearchUsage.estimated_cost_cents(events)
  end

  test ".for_feed should return only searches referenced by recent refreshes" do
    user = create(:user)
    credential = create(:search_credential, :active, user: user)
    feed = create(:feed, user: user, search_credential: credential)
    recent_refresh = Event.create!(type: "feed_refresh", level: :info, subject: feed, user: user)
    other_refresh = Event.create!(type: "feed_refresh", level: :info, subject: create(:feed), user: user)
    recent = WebSearchUsage.record!(credential: credential, refresh_event: recent_refresh)
    WebSearchUsage.record!(credential: credential, refresh_event: other_refresh)

    travel_to(WebSearchUsage::STATS_PERIOD.ago - 1.minute) do
      old_refresh = Event.create!(type: "feed_refresh", level: :info, subject: feed, user: user)
      WebSearchUsage.record!(credential: credential, refresh_event: old_refresh)
    end

    assert_equal [recent], WebSearchUsage.for_feed(feed).to_a
  end
end
