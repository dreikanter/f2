class StatusesController < ApplicationController
  def show
    @user = Current.user
    @recent_events = Event.where(user: @user).user_relevant.recent.limit(10)
  end
end
