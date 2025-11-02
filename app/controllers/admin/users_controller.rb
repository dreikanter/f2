class Admin::UsersController < ApplicationController
  layout "tailwind"

  include Pagination
  include Sortable

  SORTABLE_FIELDS = {
    email: {
      title: "Email",
      order_by: "LOWER(users.email_address)",
      direction: :asc
    },
    name: {
      title: "Name",
      order_by: "LOWER(users.name)",
      direction: :asc
    },
    feeds: {
      title: "Feeds",
      order_by: "COUNT(DISTINCT feeds.id)",
      direction: :desc
    },
    tokens: {
      title: "Tokens",
      order_by: "COUNT(DISTINCT access_tokens.id)",
      direction: :desc
    },
    posts: {
      title: "Posts",
      order_by: "COUNT(DISTINCT posts.id)",
      direction: :desc
    },
    last_seen: {
      title: "Last Seen",
      order_by: "MAX(sessions.updated_at)",
      direction: :desc
    }
  }.freeze


  def index
    authorize User
    @users = paginate_scope
  end

  def show
    @user = User.includes(:feeds, :access_tokens, :sessions, :created_invites).find(params[:id])
    authorize @user
    @stats = UserStats.new(@user)
  end

  private

  def sortable_fields
    SORTABLE_FIELDS
  end

  def sortable_path(sort_params)
    admin_users_path(request.query_parameters.merge(sort_params))
  end

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
      .order(sortable_order)
  end

  def pagination_total_count
    @pagination_total_count ||= base_scope.count
  end

  def base_scope
    policy_scope(User)
  end
end
