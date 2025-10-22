require "test_helper"

class FeedMetricTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed)
  end

  test "should be valid with all required attributes" do
    metric = build(:feed_metric)
    assert metric.valid?
  end

  test "should require feed" do
    metric = build(:feed_metric, feed: nil)
    assert_not metric.valid?
    assert metric.errors.of_kind?(:feed, :blank)
  end

  test "should require date" do
    metric = build(:feed_metric, date: nil)
    assert_not metric.valid?
    assert metric.errors.of_kind?(:date, :blank)
  end

  test "should require unique date per feed" do
    create(:feed_metric, feed: feed, date: Date.current)
    duplicate = build(:feed_metric, feed: feed, date: Date.current)
    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:date, :taken)
  end

  test "should allow same date for different feeds" do
    feed1 = create(:feed)
    feed2 = create(:feed)
    create(:feed_metric, feed: feed1, date: Date.current)

    metric2 = build(:feed_metric, feed: feed2, date: Date.current)
    assert metric2.valid?
  end

  test "should validate posts_count is non-negative" do
    metric = build(:feed_metric, posts_count: -1)
    assert_not metric.valid?
    assert metric.errors.of_kind?(:posts_count, :greater_than_or_equal_to)
  end

  test "should validate invalid_posts_count is non-negative" do
    metric = build(:feed_metric, invalid_posts_count: -1)
    assert_not metric.valid?
    assert metric.errors.of_kind?(:invalid_posts_count, :greater_than_or_equal_to)
  end

  test "should have default values of zero" do
    metric = build(:feed_metric)
    assert_equal 0, metric.posts_count
    assert_equal 0, metric.invalid_posts_count
  end

  test "#for_date_range scope returns metrics within range" do
    freeze_time do
      metric1 = create(:feed_metric, feed: feed, date: 5.days.ago.to_date, posts_count: 1)
      metric2 = create(:feed_metric, feed: feed, date: 3.days.ago.to_date, posts_count: 2)
      metric3 = create(:feed_metric, feed: feed, date: 1.day.ago.to_date, posts_count: 3)
      create(:feed_metric, feed: feed, date: 10.days.ago.to_date, posts_count: 4)

      metrics = FeedMetric.for_date_range(5.days.ago.to_date, 1.day.ago.to_date).order(:date)

      assert_equal [metric1, metric2, metric3], metrics.to_a
    end
  end

  test "#for_user scope returns metrics for user's feeds only" do
    user1 = create(:user)
    user2 = create(:user)
    feed1 = create(:feed, user: user1)
    feed2 = create(:feed, user: user2)

    metric1 = create(:feed_metric, feed: feed1, posts_count: 5)
    create(:feed_metric, feed: feed2, posts_count: 10)

    user1_metrics = FeedMetric.for_user(user1)

    assert_equal 1, user1_metrics.count
    assert_equal metric1.id, user1_metrics.first.id
  end

  test "#record should create new metric when activity exists" do
    assert_difference "FeedMetric.count", 1 do
      FeedMetric.record(
        feed: feed,
        date: Date.current,
        posts_count: 5,
        invalid_posts_count: 2
      )
    end

    metric = FeedMetric.last
    assert_equal feed.id, metric.feed_id
    assert_equal Date.current, metric.date
    assert_equal 5, metric.posts_count
    assert_equal 2, metric.invalid_posts_count
  end

  test "#record should not create metric when no activity" do
    assert_no_difference "FeedMetric.count" do
      FeedMetric.record(
        feed: feed,
        date: Date.current,
        posts_count: 0,
        invalid_posts_count: 0
      )
    end
  end

  test "#record should update existing metric via upsert" do
    create(:feed_metric, feed: feed, date: Date.current, posts_count: 3)

    assert_no_difference "FeedMetric.count" do
      FeedMetric.record(
        feed: feed,
        date: Date.current,
        posts_count: 10,
        invalid_posts_count: 5
      )
    end

    metric = FeedMetric.find_by(feed: feed, date: Date.current)
    assert_equal 10, metric.posts_count
    assert_equal 5, metric.invalid_posts_count
  end

  test "#record should create metric when only posts_count is non-zero" do
    assert_difference "FeedMetric.count", 1 do
      FeedMetric.record(
        feed: feed,
        date: Date.current,
        posts_count: 5,
        invalid_posts_count: 0
      )
    end
  end

  test "#record should create metric when only invalid_posts_count is non-zero" do
    assert_difference "FeedMetric.count", 1 do
      FeedMetric.record(
        feed: feed,
        date: Date.current,
        posts_count: 0,
        invalid_posts_count: 3
      )
    end
  end

  test "#increment_metric should create new record and increments" do
    assert_difference "FeedMetric.count", 1 do
      FeedMetric.increment_metric(
        feed: feed,
        date: Date.current,
        metric: :posts_count,
        by: 3
      )
    end

    metric = FeedMetric.find_by(feed: feed, date: Date.current)
    assert_equal 3, metric.posts_count
  end

  test "#increment_metric should increment existing record" do
    create(:feed_metric, feed: feed, date: Date.current, posts_count: 5)

    assert_no_difference "FeedMetric.count" do
      FeedMetric.increment_metric(
        feed: feed,
        date: Date.current,
        metric: :posts_count,
        by: 2
      )
    end

    metric = FeedMetric.find_by(feed: feed, date: Date.current)
    assert_equal 7, metric.posts_count
  end

  test "#increment_metric should default to incrementing by 1" do
    FeedMetric.increment_metric(
      feed: feed,
      date: Date.current,
      metric: :invalid_posts_count
    )

    metric = FeedMetric.find_by(feed: feed, date: Date.current)
    assert_equal 1, metric.invalid_posts_count
  end
end
