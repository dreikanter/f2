class FeedFilterDropdownComponent < ViewComponent::Base
  include ApplicationHelper

  def initialize(feeds:, selected_feed:, sort_params:, menu_id:)
    @feeds = feeds
    @selected_feed = selected_feed
    @sort_params = sort_params.to_h.symbolize_keys
    @menu_id = menu_id
  end

  private

  attr_reader :feeds, :selected_feed, :sort_params, :menu_id

  def button_id
    "#{menu_id}-button"
  end

  def button_label
    selected_feed&.display_name || "All feeds"
  end

  def all_feeds_path
    helpers.posts_path(sort_params)
  end

  def feed_link_path(feed)
    helpers.posts_path(sort_params.merge(feed_id: feed.id))
  end

  def trigger_classes
    "inline-flex items-center justify-center whitespace-nowrap rounded-md " \
      "border border-slate-200 bg-white px-4 py-2 text-base font-semibold text-slate-600 " \
      "shadow-sm transition hover:bg-slate-50 " \
      "focus:outline-none focus:ring-2 focus:ring-sky-500 focus:ring-offset-1 gap-2"
  end

  def panel_classes
    "z-20 hidden w-60 rounded-lg border border-slate-200 bg-white shadow-sm"
  end

  def item_classes(active)
    helpers.class_names(
      "flex w-full items-center px-4 py-2 transition hover:bg-slate-50 focus:bg-slate-100 focus:outline-none",
      "font-semibold text-slate-900": active
    )
  end
end
