class EventsController < ApplicationController
  before_action :require_authentication

  def index
    authorize Event

    page = (params[:page] || 1).to_i
    per_page = 25
    offset = (page - 1) * per_page

    @events = policy_scope(Event).includes(:user, :subject)
                                 .order(created_at: :desc)
                                 .limit(per_page)
                                 .offset(offset)

    @total_count = policy_scope(Event).count
    @current_page = page
    @total_pages = (@total_count.to_f / per_page).ceil
    @per_page = per_page
  end

  def show
    @event = Event.find(params[:id])
    authorize @event

    # Find next and previous events for navigation
    @previous_event = policy_scope(Event).where("created_at > ?", @event.created_at)
                                        .order(created_at: :asc)
                                        .first
    
    @next_event = policy_scope(Event).where("created_at < ?", @event.created_at)
                                    .order(created_at: :desc)
                                    .first
  end
end
