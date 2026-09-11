# The compact event list. The status page renders it and the brief polling
# stream replaces it, so both must select the same rows; reading them from one
# place is what keeps that true.
module BriefEventList
  extend ActiveSupport::Concern

  included do
    class_attribute :brief_events_limit, default: 15
  end

  private

  # Preload event_references so feed refresh descriptions can count imported
  # posts without an extra query per row.
  def brief_events(scope)
    scope.includes(:user, :subject, :event_references)
         .order(created_at: :desc, id: :desc)
         .limit(brief_events_limit)
  end
end
