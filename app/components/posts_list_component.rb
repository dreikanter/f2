class PostsListComponent < ViewComponent::Base
  def initialize(posts:, show_feed: false, card_component: PostCardComponent)
    @posts = posts
    @show_feed = show_feed
    @card_component = card_component
  end

  def call
    content_tag(:div, class: "space-y-4") do
      safe_join(@posts.map { |post| render(@card_component.new(post: post, show_feed: @show_feed)) })
    end
  end
end
