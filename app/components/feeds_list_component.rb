class FeedsListComponent < ListComponent
  def initialize(feeds:, admin: false)
    super()
    @feeds = feeds
    @admin = admin
  end

  def before_render
    @feeds.each { |feed| with_item(FeedListItemComponent.new(feed: feed, admin: @admin)) }
  end
end
