module Admin
  # Points an event description's entity links at the operator-facing pages,
  # so admins can follow them to any user's records. Mixed into the admin
  # event description components.
  module EventEntityLinks
    private

    def feed_link_path(feed)
      helpers.admin_feed_path(feed)
    end

    def access_token_link_path(access_token)
      helpers.admin_access_token_path(access_token)
    end

    def ai_credential_link_path(credential)
      helpers.admin_ai_credential_path(credential)
    end

    def search_credential_link_path(credential)
      helpers.admin_search_credential_path(credential)
    end
  end
end
