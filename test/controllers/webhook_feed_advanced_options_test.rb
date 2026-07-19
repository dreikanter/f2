require "test_helper"

class WebhookFeedAdvancedOptionsTest < ActionDispatch::IntegrationTest
  test "advanced options submitted for a webhook feed are ignored" do
    user = create(:user)
    feed = create(:feed, :webhook, :draft, user: user)
    sign_in_as(user)

    patch feed_path(feed), params: {
      feed: {
        import_after_enabled: "1",
        import_after_date: "2026-01-01",
        import_after_time: "12:34",
        images_only: "1"
      },
      enable_feed: "0"
    }

    assert_redirected_to feed_path(feed)

    feed.reload
    assert_equal false, feed[:import_after_enabled]
    assert_nil feed[:import_after_date]
    assert_nil feed[:import_after_time]
    assert_equal false, feed[:images_only]
  end

  test "advanced option readers remain inert for legacy webhook values" do
    feed = create(:feed, :webhook, :draft)
    feed.update_columns(
      import_after_enabled: true,
      import_after_date: Date.new(2026, 1, 1),
      import_after_time: "12:34",
      images_only: true
    )

    feed.reload
    assert_not feed.import_after_enabled
    assert_nil feed.import_after_date
    assert_nil feed.import_after_time
    assert_not feed.images_only
  end
end
