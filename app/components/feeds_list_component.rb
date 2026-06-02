class FeedsListComponent < ViewComponent::Base
  def initialize(feeds:)
    @feeds = feeds
  end

  def call
    content_tag(:div, class: "space-y-3") do
      safe_join(@feeds.map { |feed| render(FeedCardComponent.new(feed: feed)) })
    end
  end
end
