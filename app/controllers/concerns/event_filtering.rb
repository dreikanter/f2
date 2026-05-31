module EventFiltering
  extend ActiveSupport::Concern

  private

  # Narrows an events relation by the permitted `filter` query params. Returns
  # the scope untouched when no filter is present.
  def apply_filters(scope)
    optional_filter.blank? ? scope : scope.where(**optional_filter)
  end

  def optional_filter
    @optional_filter ||= params.fetch(:filter, {}).permit(*permitted_filter_keys)
  end

  # Controllers override this to expose additional filters (e.g. admins can
  # filter by user_id, while a user's own log is already scoped to them).
  def permitted_filter_keys
    [:subject_type, :subject_id, :level, { type: [] }]
  end
end
