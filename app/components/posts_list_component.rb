class PostsListComponent < ListComponent
  # `view_all_url` appends a "View all" row linking to the full posts list.
  def initialize(posts:, show_feed: false, item_component: PostListItemComponent, view_all_url: nil)
    super()
    @posts = posts
    @show_feed = show_feed
    @item_component = item_component
    @view_all_url = view_all_url
  end

  def before_render
    @posts.each { |post| with_item(@item_component.new(post: post, show_feed: @show_feed)) }
    with_item(ViewAllListItemComponent.new(url: @view_all_url, data: { key: "posts.view_all" })) if @view_all_url
  end
end
