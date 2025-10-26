class Admin::EventsController < ApplicationController
  include Pagination

  def index
    authorize Event

    @filter = optional_filter
    @events = paginate_scope.includes(:user, :subject)
  end

  def show
    authorize Event
    @event = Event.find(params[:id])
    @previous_event = previous_event(@event)
    @next_event = next_event(@event)
  end

  private

  def pagination_scope
    events_scope.order(created_at: :desc)
  end

  def previous_event(event)
    events_scope.where("id > ?", event.id).order(id: :asc).first
  end

  def next_event(event)
    events_scope.where("id < ?", event.id).order(id: :desc).first
  end

  def events_scope
    apply_filters(policy_scope(Event))
  end

  def apply_filters(scope)
    return scope if optional_filter.blank?

    filter = optional_filter.dup

    # Handle type filter separately to support both single values and arrays
    if filter.key?(:type)
      types = filter.delete(:type)
      scope = scope.where(type: types) if types.present?
    end

    filter.blank? ? scope : scope.where(**filter)
  end

  def optional_filter
    @optional_filter ||= params.fetch(:filter, {}).permit(:user_id, :subject_type, :level, :type, type: [])
  end
end
