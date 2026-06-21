class PostsListComponent < ListComponent
  def initialize(posts:, show_feed: false, item_component: PostListItemComponent)
    super()
    @posts = posts
    @show_feed = show_feed
    @item_component = item_component
  end

  def before_render
    @posts.each { |post| with_item(@item_component.new(post: post, show_feed: @show_feed)) }
  end
end
