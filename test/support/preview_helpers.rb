module PreviewHelpers
  # Seed the persisted proof the enable gate now looks for.
  def seed_ready_preview(feed, ready_at: Time.current)
    create(:feed_preview, :completed,
           user: feed.user,
           feed_profile_key: feed.feed_profile_key,
           params: feed.params,
           ready_at: ready_at)
  end
end
