class StatusesController < ApplicationController
  include EventFiltering

  class_attribute :initial_events_limit, default: 15

  def show
    @user = Current.user
    @filter = optional_filter
    @recent_events = recent_events
  end

  private

  def recent_events
    apply_filters(Event.where(user: @user).user_relevant)
      .includes(:user, :subject, :event_references)
      .order(created_at: :desc, id: :desc)
      .limit(initial_events_limit)
  end
end
