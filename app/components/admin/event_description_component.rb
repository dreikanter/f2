module Admin
  # Admin variant of EventDescriptionComponent: identical rendering, but feed
  # references point at the operator-facing feed page. The per-type subclasses
  # mirror the user-facing ones so refresh counts and reason copy still render.
  class EventDescriptionComponent < ::EventDescriptionComponent
    include FeedLinks

    SUBCLASSES = {
      "feed_refresh" => "Admin::FeedRefreshDescriptionComponent",
      "feed_auto_disabled" => "Admin::FeedAutoDisabledDescriptionComponent",
      "feed_target_group_unavailable" => "Admin::FeedTargetGroupUnavailableDescriptionComponent"
    }.freeze
  end
end
