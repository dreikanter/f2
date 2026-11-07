# Interactive feed changes share a row lock and commit their events atomically.
# Controllers enqueue refreshes after a successful transition has committed.
class Feed::StateTransition
  # changed refers to the feed's state, rather than edits to other attributes.
  Result = Data.define(:success, :changed) do
    def success?
      success
    end

    def changed?
      changed
    end
  end

  def initialize(feed)
    @feed = feed
  end

  def enable(reset_schedule: false)
    @feed.with_lock do
      result = persist { @feed.enable }
      @feed.reset_schedule! if result.success? && reset_schedule
      result
    end
  end

  def disable
    @feed.with_lock { persist { @feed.disable } }
  end

  # Assign form changes after acquiring the lock, including a requested pause.
  def update
    @feed.with_lock do
      yield @feed
      persist { @feed.save }
    end
  end

  private

  def persist
    return Result.new(success: false, changed: false) unless yield

    changed = @feed.saved_change_to_state?
    record_event if changed
    Result.new(success: true, changed: changed)
  end

  def record_event
    Event.create!(
      type: "feed_#{@feed.state}",
      level: @feed.enabled? ? :info : :warning,
      subject: @feed,
      user: @feed.user
    )
  end
end
