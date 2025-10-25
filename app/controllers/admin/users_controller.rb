class Admin::UsersController < ApplicationController
  include Pagination
  include Sortable

  sortable_by({
    "email" => "LOWER(users.email_address)",
    "name" => "LOWER(users.name)",
    "feeds" => "COUNT(DISTINCT feeds.id)",
    "tokens" => "COUNT(DISTINCT access_tokens.id)",
    "posts" => "COUNT(DISTINCT posts.id)",
    "last_seen" => "MAX(sessions.updated_at)"
  }, default_column: :email, default_direction: :desc)

  def index
    authorize User
    @users = paginate_scope
  end

  def show
    @user = User.find(params[:id])
    authorize @user
  end

  def reactivate_email
    @user = User.find(params[:id])
    authorize @user
    @user.reactivate_email!
    redirect_to admin_user_path(@user), notice: "Email reactivated successfully."
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
      .order(sort_order)
  end

  def pagination_total_count
    @pagination_total_count ||= base_scope.count
  end

  def base_scope
    policy_scope(User)
  end
end
