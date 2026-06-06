class FeedCardComponent < ViewComponent::Base
  DISCARD_CONFIRM = "Discard this draft? No data will be lost since it hasn't been activated.".freeze

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

  def draft?
    feed.draft?
  end

  def status_badge
    case feed.state.to_sym
    when :draft    then BadgeComponent.new(text: "Draft", color: :gray, key: "feed.#{feed.id}.draft_badge")
    when :disabled then BadgeComponent.new(text: "Disabled", color: :yellow, key: "feed.#{feed.id}.disabled_badge")
    when :enabled  then BadgeComponent.new(text: "Active", color: :green, key: "feed.#{feed.id}.enabled_badge")
    end
  end

  def menu_id
    "feed-menu-#{feed.id}"
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
