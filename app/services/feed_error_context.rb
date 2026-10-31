class FeedErrorContext
  def self.for(feed)
    owner = feed.user

    {
      feed_id: feed.id,
      feed_owner_id: feed.user_id,
      feed_owner_label: owner.name.presence || owner.anonymized_email,
      freefeed_instance: feed.access_token&.host_domain,
      target_group: feed.target_group
    }.compact
  end
end
