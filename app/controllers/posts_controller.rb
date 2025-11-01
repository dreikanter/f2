class PostsController < ApplicationController
  include Pagination
  include Sortable

  layout "tailwind"

  SORTABLE_FIELDS = {
    published: {
      title: "Published",
      order_by: "posts.published_at",
      direction: :desc
    },
    feed: {
      title: "Feed",
      order_by: "LOWER(feeds.name)",
      direction: :asc
    },
    status: {
      title: "Status",
      order_by: "posts.status",
      direction: :asc
    },
    attachments: {
      title: "Attachments",
      order_by: "COALESCE(array_length(posts.attachment_urls, 1), 0)",
      direction: :desc
    },
    comments: {
      title: "Comments",
      order_by: "COALESCE(array_length(posts.comments, 1), 0)",
      direction: :desc
    }
  }.freeze

  def index
    authorize Post
    @sortable_presenter = sortable_presenter
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

  def sortable_fields
    SORTABLE_FIELDS
  end

  def sortable_path(sort_params)
    posts_path(sort_params.merge(params.permit(:feed_id).to_h))
  end

  def pagination_scope
    scope = policy_scope(Post).preload(feed: :access_token).order(sortable_order)
    scope = scope.where(feed_id: params[:feed_id]) if params[:feed_id].present?
    scope
  end

  def load_post
    policy_scope(Post).preload(feed: :access_token).find(params[:id])
  end
end
