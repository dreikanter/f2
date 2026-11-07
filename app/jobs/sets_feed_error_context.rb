module SetsFeedErrorContext
  private

  # Keep context through the job's outer error handlers; the Rails executor clears it.
  def set_feed_error_context(feed)
    owner = feed.user
    context = {
      feed_id: feed.id,
      feed_owner_id: feed.user_id,
      feed_owner_label: owner.name.presence || owner.anonymized_email,
      freefeed_instance: feed.access_token&.host_domain,
      target_group: feed.target_group
    }.compact

    Rails.error.set_context(**context)
  end
end
