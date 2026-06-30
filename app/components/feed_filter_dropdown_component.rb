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

  def item_classes(active)
    helpers.class_names(
      "flex w-full items-center px-4 py-2 transition hover:bg-surface-muted focus:bg-surface-sunken focus:outline-none",
      "font-semibold text-slate-900": active
    )
  end
end
