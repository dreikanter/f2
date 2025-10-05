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

  def destroy
    @post = load_post
    authorize @post

    access_token = @post.feed.access_token
    client = FreefeedClient.new(host: access_token.host, token: access_token.token_value)

    begin
      client.delete_post(@post.freefeed_post_id)
      @post.update!(status: :deleted)
      redirect_to posts_path, notice: "Post unpublished successfully. It remains visible in the app."
    rescue FreefeedClient::Error => e
      redirect_to post_path(@post), alert: "Failed to unpublish post: #{e.message}"
    end
  end

  private

  def pagination_scope
    policy_scope(Post).includes(:feed).order(published_at: :desc)
  end

  def load_post
    policy_scope(Post).find(params[:id])
  end
end
