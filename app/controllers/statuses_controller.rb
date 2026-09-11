class StatusesController < ApplicationController
  include EventFiltering
  include BriefEventList

  def show
    @user = Current.user
    @filter = optional_filter
    @recent_events = brief_events(apply_filters(Event.where(user: @user).user_relevant))
  end
end
