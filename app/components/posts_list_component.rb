class PostsListComponent < ViewComponent::Base
  def initialize(posts:, show_feed: false)
    @posts = posts
    @show_feed = show_feed
  end

  def call
    content_tag(:div, class: "space-y-4") do
      safe_join(@posts.map { |post| render(PostCardComponent.new(post: post, show_feed: @show_feed)) })
    end
  end
end
