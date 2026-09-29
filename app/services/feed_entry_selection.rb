# Selects first-seen identities using a feed's history and import threshold.
class FeedEntrySelection
  attr_reader :stats

  def initialize(feed, history_feed: feed)
    @feed = feed
    @history_feed = history_feed
    @stats = {}
  end

  def call(entries)
    unique = entries.uniq(&:uid)
    @stats[:collapsed_duplicate_uids] = entries.size - unique.size
    known = if @history_feed&.persisted? && unique.any?
      FeedEntryUid.where(feed_id: @history_feed.id, uid: unique.map(&:uid)).pluck(:uid).to_set
    else
      Set.new
    end
    new_entries = unique.reject { |entry| known.include?(entry.uid) }
    @stats[:known_entries] = unique.size - new_entries.size
    selected = new_entries.select do |entry|
      @feed.import_after.nil? || entry.published_at.nil? || entry.published_at > @feed.import_after
    end
    @stats[:entries_before_threshold] = new_entries.size - selected.size
    selected
  end
end
