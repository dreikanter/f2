module FixtureFeedEntries
  def fixture_dir
    raise NotImplementedError, "#{self.class} must implement #fixture_dir"
  end

  def processor_class
    raise NotImplementedError, "#{self.class} must implement #processor_class"
  end

  # Source payload filename within fixture_dir; override for non-XML feeds.
  def fixture_file
    "feed.xml"
  end

  def feed
    @feed ||= create(:feed)
  end

  def processor
    raw = file_fixture("#{fixture_dir}/#{fixture_file}").read
    processor_class.new(feed, raw)
  end

  def feed_entries
    @feed_entries ||= processor.process.entries
  end

  def feed_entry(index)
    entry = feed_entries[index]
    entry.save!
    entry
  end
end
