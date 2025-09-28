class PostsController < ApplicationController
  include Pagination

  def index
    authorize Post
    @posts = paginate_scope
  end

  def show
    @post = load_post
    authorize @post
  end

  private

  def pagination_scope
    policy_scope(Post).includes(:feed).order(published_at: :desc)
  end

  def load_post
    policy_scope(Post).find(params[:id])
  end
end
