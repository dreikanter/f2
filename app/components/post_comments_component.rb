class PostCommentsComponent < ViewComponent::Base
  def initialize(post:)
    @post = post
  end

  def render?
    comments.present?
  end

  def comments
    @post.comments
  end
end
