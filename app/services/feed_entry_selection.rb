# Applies feed history, date thresholds, and AI post limits.
class FeedEntrySelection
  attr_reader :stats, :posts

  def initialize(feed, history_feed: feed)
    @feed = feed
    @history_feed = history_feed
    @stats = {}
    @posts = {}
  end

  def call(entries)
    entries = usable_entries(entries) if @feed.feed_profile_key == "llm"
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
    if @feed.feed_profile_key == "llm"
      limited = selected.first(LlmOutput.new(@feed).max_items)
      @stats[:overflow_entries] = selected.size - limited.size
      selected = limited
      @posts.slice!(*selected.map(&:uid))
    end
    @stats[:selected_entries] = selected.size
    selected
  end

  private

  def usable_entries(entries)
    @posts = {}
    usable = entries.select do |entry|
      post = @feed.normalizer_instance(entry).normalize
      @posts[entry.uid] ||= post if post.enqueued?
      post.enqueued?
    end
    @stats[:rejected_posts] = entries.size - usable.size
    usable
  end
end
