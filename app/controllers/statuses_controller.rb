class StatusesController < ApplicationController
  class_attribute :initial_events_limit, default: 20

  def show
    @user = Current.user
    @recent_events = Event.where(user: @user).user_relevant.order(id: :desc).limit(initial_events_limit)
  end
end
