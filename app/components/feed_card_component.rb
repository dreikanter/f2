class FeedCardComponent < ViewComponent::Base
  DISCARD_CONFIRM = "Discard this draft? No data will be lost since it hasn't been activated.".freeze
  ENABLE_CONFIRM = "Enable this feed?".freeze
  DISABLE_CONFIRM = "Disable this feed?".freeze

  def initialize(feed:)
    @feed = feed
  end

  private

  attr_reader :feed

  def title
    feed.display_name
  end

  def feed_url
    helpers.feed_path(feed)
  end

  def edit_url
    helpers.edit_feed_path(feed)
  end

  def status_url
    helpers.feed_status_path(feed)
  end

  def draft?
    feed.draft?
  end

  def enabled?
    feed.enabled?
  end

  def can_be_enabled?
    feed.can_be_enabled?
  end

  def status_badge
    helpers.feed_status_badge(feed)
  end

  def menu_id
    "feed-menu-#{feed.id}"
  end

  # Query-shaped profiles (AI search) have no URL to open, so the menu only
  # offers a source link when the feed's input is an actual URL.
  def source_url
    feed.source_input.presence if feed.source_input_shape == "url"
  end

  def target_group_label
    "@#{feed.target_group}" if feed.target_group.present?
  end

  def target_group_url
    return unless feed.access_token && feed.target_group.present?

    "#{feed.access_token.host}/#{feed.target_group}"
  end

  def last_refreshed_tag
    return "Never" unless feed.last_refreshed_at

    helpers.short_time_ago_tag(feed.last_refreshed_at)
  end

  def most_recent_post_tag
    return "None" unless feed.most_recent_post_date

    helpers.short_time_ago_tag(feed.most_recent_post_date)
  end
end
