class PostsController < ApplicationController
  include Pagination

  def index
    authorize Post
    @posts = paginate_scope
    @feed = Feed.find(params[:feed_id]) if params[:feed_id].present?
  end

  def show
    @post = load_post
    authorize @post
  end

  def destroy
    @post = load_post
    authorize @post

    @post.withdrawn!
    PostWithdrawalJob.perform_later(@post.id)

    Event.create!(
      type: "PostWithdrawn",
      user: Current.user,
      subject: @post,
      level: :info
    )

    respond_to do |format|
      format.html { redirect_to posts_path, notice: "Post withdrawal initiated. It remains visible in the app." }
      format.turbo_stream
    end
  end

  private

  def pagination_scope
    scope = policy_scope(Post).includes(:feed).order(published_at: :desc)
    scope = scope.where(feed_id: params[:feed_id]) if params[:feed_id].present?
    scope
  end

  def load_post
    policy_scope(Post).find(params[:id])
  end
end
