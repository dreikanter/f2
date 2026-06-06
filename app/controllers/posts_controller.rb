class PostsController < ApplicationController
  include Pagination
  include Sortable

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
    @feeds = policy_scope(Feed).order(:name)
  end

  def show
    @post = load_post
    authorize @post
  end

  def destroy
    @post = load_post
    authorize @post

    @delete_freefeed = boolean_param(:delete_freefeed)
    @delete_record = boolean_param(:delete_record)

    unless @delete_freefeed || @delete_record
      return respond_to do |format|
        format.html { redirect_to posts_path, alert: "Pick at least one thing to delete." }
        format.turbo_stream { head :no_content }
      end
    end

    if @delete_freefeed && @post.freefeed_post_id.present?
      PostWithdrawalJob.perform_later(@post.feed_id, @post.freefeed_post_id, @post.id)
    end

    if @delete_record
      delete_post_record(@post)
    else
      @post.withdrawn!
      log_post_event("post_withdrawn", @post)
    end

    @notice = destroy_notice

    respond_to do |format|
      format.html { redirect_to posts_path, notice: @notice }
      format.turbo_stream
    end
  end

  private

  def boolean_param(key)
    ActiveModel::Type::Boolean.new.cast(params[key])
  end

  # Removes Feeder's record of the post, including the source entry and its
  # import marker, so the item can be picked up again on the next feed refresh.
  def delete_post_record(post)
    feed = post.feed
    feed_entry = post.feed_entry
    uid = post.uid

    ActiveRecord::Base.transaction do
      if feed_entry
        feed_entry.destroy! # cascades to the post via dependent: :destroy
      else
        post.destroy!
      end
      FeedEntryUid.where(feed_id: feed.id, uid: uid).delete_all
      log_post_event("post_deleted", post, subject: feed)
    end
  end

  def log_post_event(type, post, subject: post)
    Event.create!(type: type, user: Current.user, subject: subject, level: :info)
  end

  def destroy_notice
    if @delete_record && @delete_freefeed
      "Post removed from FreeFeed and Feeder. It may be imported again the next time the feed updates."
    elsif @delete_record
      "Post record deleted. It may be imported again the next time the feed updates."
    else
      "The post will be withdrawn from FreeFeed but stays here so it won't be imported again."
    end
  end

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
