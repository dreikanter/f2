class EventsController < ApplicationController
  before_action :require_authentication

  PER_PAGE = 25

  def index
    authorize Event
    load_events_for_index
  end

  def show
    authorize Event
    @event = Event.find(params[:id])
    load_navigation_events
  end

  private

  def load_events_for_index
    page = (params[:page] || 1).to_i
    offset = (page - 1) * PER_PAGE

    @events = Event.includes(:user, :subject)
                   .order(created_at: :desc)
                   .limit(PER_PAGE)
                   .offset(offset)

    @total_count = Event.count
    @current_page = page
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @per_page = PER_PAGE
  end

  def load_navigation_events
    @previous_event = Event.where("id > ?", @event.id).order(id: :asc).first
    @next_event = Event.where("id < ?", @event.id).order(id: :desc).first
  end
end
