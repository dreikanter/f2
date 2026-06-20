module Admin
  # Points an event description's feed links at the operator-facing feed page,
  # so admins can follow them to any user's feed. Mixed into the admin event
  # description components.
  module FeedLinks
    private

    def feed_link_path(feed)
      helpers.admin_feed_path(feed)
    end
  end
end
