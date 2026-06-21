class FeedsListComponent < ViewComponent::Base
  def initialize(feeds:, admin: false)
    @feeds = feeds
    @admin = admin
  end

  def call
    render(ListComponent.new) do |list|
      @feeds.each { |feed| list.with_item(FeedCardComponent.new(feed: feed, admin: @admin)) }
    end
  end
end
