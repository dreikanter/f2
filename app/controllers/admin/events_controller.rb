class Admin::EventsController < ApplicationController
  PER_PAGE = 25

  def index
    authorize Event

    page = (params[:page] || 1).to_i
    offset = (page - 1) * PER_PAGE

    @filter_query = parse_filter_query
    @events = paginated_events(offset)
    @total_count = events_count
    @current_page = page
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @per_page = PER_PAGE
  end

  def show
    authorize Event
    @event = Event.find(params[:id])
    @previous_event = previous_event(@event)
    @next_event = next_event(@event)
  end

  private

  def paginated_events(offset)
    events_scope
      .includes(:user, :subject)
      .order(created_at: :desc)
      .limit(PER_PAGE)
      .offset(offset)
  end

  def events_count
    events_scope.count
  end

  def previous_event(event)
    events_scope.where("id > ?", event.id).order(id: :asc).first
  end

  def next_event(event)
    events_scope.where("id < ?", event.id).order(id: :desc).first
  end

  def events_scope
    scope = policy_scope(Event)
    scope = apply_filters(scope)
    scope
  end

  def parse_filter_query
    return {} unless params[:filter_query].present?

    begin
      JSON.parse(params[:filter_query])
    rescue JSON::ParserError
      {}
    end
  end

  def apply_filters(scope)
    return scope if @filter_query.blank?

    @filter_query.each do |attribute, value|
      case attribute
      when "type"
        scope = scope.where(type: value) if value.present?
      when "subject_type"
        scope = scope.where(subject_type: value) if value.present?
      when "level"
        scope = scope.where(level: value) if value.present?
      end
    end

    scope
  end
end
