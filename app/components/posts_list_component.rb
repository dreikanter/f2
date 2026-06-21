class PostsListComponent < ViewComponent::Base
  def initialize(posts:, show_feed: false, item_component: PostListItemComponent)
    @posts = posts
    @show_feed = show_feed
    @item_component = item_component
  end

  def call
    render(ListComponent.new) do |list|
      @posts.each { |post| list.with_item(@item_component.new(post: post, show_feed: @show_feed)) }
    end
  end
end
