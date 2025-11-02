class UserStats
  attr_reader :user, :last_session, :sessions, :feeds_count, :feeds_enabled_count,
              :feeds_disabled_count, :access_tokens_count, :active_access_tokens_count,
              :inactive_access_tokens_count, :posts_count, :most_recent_post,
              :created_invites_count, :invited_users_count, :invited_users

  def initialize(user)
    @user = user
    load_stats
  end

  private

  def load_stats
    load_session_stats
    load_feeds_stats
    load_access_tokens_stats
    load_posts_stats
    load_invitations_stats
  end

  def load_session_stats
    @sessions = user.sessions.order(updated_at: :desc).to_a
    @last_session = @sessions.first
  end

  def load_feeds_stats
    @feeds_count = user.feeds.size
    @feeds_enabled_count = user.feeds.count(&:enabled?)
    @feeds_disabled_count = user.feeds.count(&:disabled?)
  end

  def load_access_tokens_stats
    @access_tokens_count = user.access_tokens.size
    @active_access_tokens_count = user.access_tokens.count(&:active?)
    @inactive_access_tokens_count = @access_tokens_count - @active_access_tokens_count
  end

  def load_posts_stats
    @posts_count = Post.joins(:feed).where(feeds: { user_id: user.id }).count
    @most_recent_post = Post.joins(:feed).where(feeds: { user_id: user.id }).order(published_at: :desc).first
  end

  def load_invitations_stats
    @created_invites_count = user.created_invites.size
    @invited_users_count = user.created_invites.count { |i| i.invited_user_id.present? }
    @invited_users = user.created_invites.includes(:invited_user).where.not(invited_user_id: nil).order(created_at: :desc).to_a
  end
end
