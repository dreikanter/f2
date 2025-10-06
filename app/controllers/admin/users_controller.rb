class Admin::UsersController < ApplicationController
  include Pagination

  def index
    authorize User
    @users = paginate_scope
  end

  def show
    @user = User.find(params[:id])
    authorize @user
  end

  private

  def pagination_scope
    base_scope
      .left_joins(:feeds, :access_tokens, :sessions)
      .left_joins(feeds: :posts)
      .group("users.id")
      .select("users.*,
               COUNT(DISTINCT feeds.id) AS feeds_count,
               COUNT(DISTINCT access_tokens.id) AS access_tokens_count,
               COUNT(DISTINCT posts.id) AS posts_count,
               MAX(sessions.updated_at) AS last_seen_at")
      .order(created_at: :desc)
  end

  def pagination_total_count
    @pagination_total_count ||= base_scope.count
  end

  def base_scope
    policy_scope(User)
  end
end
