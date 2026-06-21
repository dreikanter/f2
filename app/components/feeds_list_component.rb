class FeedsListComponent < ViewComponent::Base
  def initialize(feeds:, admin: false)
    @feeds = feeds
    @admin = admin
  end

  def call
    content_tag(:div, class: "space-y-4") do
      safe_join(@feeds.map { |feed| render(FeedCardComponent.new(feed: feed, admin: @admin)) })
    end
  end
end
