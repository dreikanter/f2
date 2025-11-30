class StatusesController < ApplicationController
  def show
    @user = Current.user
    @has_active_tokens = @user.access_tokens.active.any?
    @has_feeds = @user.total_feeds_count > 0
    @recent_events = Event.where(user: @user).user_relevant.recent.limit(10)
  end
end
