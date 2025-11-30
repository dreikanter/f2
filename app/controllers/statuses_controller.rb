class StatusesController < ApplicationController
  def show
    locals = {
      recent_events: recent_events,
      has_active_tokens: has_active_tokens?,
      no_feeds: no_feeds?
    }

    render locals: locals
  end

  private

  def recent_events
    Event.where(user: current_user).user_relevant.recent.limit(10)
  end

  def has_active_tokens?
    current_user.access_tokens.active.any?
  end

  def no_feeds?
    current_user.total_feeds_count.zero?
  end
end
