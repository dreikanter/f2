class FeedCardComponent < ViewComponent::Base
  CONTINUE_SETUP_CLASSES = "inline-flex items-center justify-center whitespace-nowrap rounded-md bg-sky-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm transition hover:bg-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-500 focus:ring-offset-1".freeze
  DISCARD_CLASSES = "inline-flex items-center justify-center whitespace-nowrap rounded-md bg-white px-3 py-1.5 text-sm font-semibold text-slate-700 shadow-sm ring-1 ring-inset ring-slate-300 transition hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-sky-500 focus:ring-offset-1 cursor-pointer disabled:cursor-not-allowed disabled:opacity-50".freeze
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

  def target_group_label
    "@#{feed.target_group}" if feed.target_group.present?
  end

  def target_group_url
    return unless feed.access_token && feed.target_group.present?

    "#{feed.access_token.host}/#{feed.target_group}"
  end

  def last_refreshed_tag
    return "Never" unless feed.last_refreshed_at

    helpers.content_tag(:time, "#{helpers.short_time_ago(feed.last_refreshed_at)} ago",
                        datetime: feed.last_refreshed_at.rfc3339,
                        title: helpers.long_time_format(feed.last_refreshed_at))
  end

  def most_recent_post_tag
    return "None" unless feed.most_recent_post_date

    helpers.content_tag(:time, "#{helpers.short_time_ago(feed.most_recent_post_date)} ago",
                        datetime: feed.most_recent_post_date.rfc3339,
                        title: helpers.long_time_format(feed.most_recent_post_date))
  end
end
