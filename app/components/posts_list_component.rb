class PostsListComponent < ViewComponent::Base
  def initialize(posts:, show_feed: false, card_component: PostCardComponent)
    @posts = posts
    @show_feed = show_feed
    @card_component = card_component
  end

  def call
    render(ListComponent.new) do |list|
      @posts.each { |post| list.with_item(@card_component.new(post: post, show_feed: @show_feed)) }
    end
  end
end
