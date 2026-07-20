module EventFiltering
  extend ActiveSupport::Concern

  included do
    helper_method :event_entity_paths
  end

  private

  # Resolves filter references to the owner-facing entity pages. Admin
  # controllers override this with Admin::EventEntityPaths so the same
  # summary links to the operator pages instead.
  def event_entity_paths
    EventEntityPaths.new
  end

  # Narrows an events relation by the permitted `filter` query params. Returns
  # the scope untouched when no filter is present.
  def apply_filters(scope)
    optional_filter.blank? ? scope : scope.where(**optional_filter)
  end

  def optional_filter
    @optional_filter ||= filter_params.permit(*permitted_filter_keys)
  end

  # `filter` may arrive malformed (e.g. `?filter=bad`); only a nested hash is
  # permittable, anything else is treated as no filter.
  def filter_params
    filter = params[:filter]
    filter.is_a?(ActionController::Parameters) ? filter : ActionController::Parameters.new
  end

  # Controllers override this to expose additional filters (e.g. admins can
  # filter by user_id, while a user's own log is already scoped to them).
  def permitted_filter_keys
    [:subject_type, :subject_id, :level, { type: [] }]
  end
end
