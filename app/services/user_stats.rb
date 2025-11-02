class UserStats
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def sessions
    @sessions ||= user.sessions.order(updated_at: :desc).to_a
  end

  def last_session
    sessions.first
  end

  def feeds_count
    @feeds_count ||= user.feeds.size
  end

  def feeds_enabled_count
    @feeds_enabled_count ||= user.feeds.count(&:enabled?)
  end

  def feeds_disabled_count
    @feeds_disabled_count ||= user.feeds.count(&:disabled?)
  end

  def access_tokens_count
    @access_tokens_count ||= user.access_tokens.size
  end

  def active_access_tokens_count
    @active_access_tokens_count ||= user.access_tokens.count(&:active?)
  end

  def inactive_access_tokens_count
    @inactive_access_tokens_count ||= access_tokens_count - active_access_tokens_count
  end

  def posts_count
    @posts_count ||= Post.joins(:feed).where(feeds: { user_id: user.id }).count
  end

  def most_recent_post
    @most_recent_post ||= Post.joins(:feed).where(feeds: { user_id: user.id }).order(published_at: :desc).first
  end

  def created_invites_count
    @created_invites_count ||= user.created_invites.size
  end

  def invited_users_count
    @invited_users_count ||= user.created_invites.count { |i| i.invited_user_id.present? }
  end

  def invited_users
    @invited_users ||= user.created_invites.includes(:invited_user).where.not(invited_user_id: nil).order(created_at: :desc).to_a
  end
end
