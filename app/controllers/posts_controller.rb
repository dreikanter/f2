class PostsController < ApplicationController
  include Pagination
  include Sortable

  layout "tailwind"

  sortable_by({
    "feed" => "LOWER(feeds.name)",
    "published" => "posts.published_at",
    "status" => "posts.status",
    "attachments" => "COALESCE(array_length(posts.attachment_urls, 1), 0)",
    "comments" => "COALESCE(array_length(posts.comments, 1), 0)"
  }, default_column: :published, default_direction: :desc)

  def index
    authorize Post
    base_params = params.permit(:feed_id).to_h.symbolize_keys

    @sort_presenter = SortPresenter.new(
      controller: self,
      columns: {
        "Published" => "published",
        "Feed" => "feed",
        "Status" => "status",
        "Attachments" => "attachments",
        "Comments" => "comments"
      },
      default_column: controller.default_sort_column,
      default_direction: controller.default_sort_direction,
      path_builder: ->(params) { posts_path(params) },
      base_params: base_params
    )

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
    scope = policy_scope(Post).preload(feed: :access_token).order(sort_order)
    scope = scope.where(feed_id: params[:feed_id]) if params[:feed_id].present?
    scope
  end

  def load_post
    policy_scope(Post).find(params[:id])
  end
end
