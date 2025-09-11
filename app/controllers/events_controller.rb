class EventsController < ApplicationController
  before_action :require_authentication
  before_action :authorize_events

  PER_PAGE = 25

  def index
    page = (params[:page] || 1).to_i
    offset = (page - 1) * PER_PAGE

    @events = events_scope.includes(:user, :subject)
                          .order(created_at: :desc)
                          .limit(PER_PAGE)
                          .offset(offset)

    @total_count = events_scope.count
    @current_page = page
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @per_page = PER_PAGE
  end

  def show
    @event = Event.find(params[:id])

    # Find next and previous events for navigation
    @previous_event = events_scope.where("created_at > ?", @event.created_at)
                                  .order(created_at: :asc)
                                  .first
    
    @next_event = events_scope.where("created_at < ?", @event.created_at)
                              .order(created_at: :desc)
                              .first
  end

  private

  def authorize_events
    authorize Event
  end

  def events_scope
    Event.all
  end
end
