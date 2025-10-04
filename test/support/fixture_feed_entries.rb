module FixtureFeedEntries
  def fixture_file_name
    raise NotImplementedError, "#{self.class} must implement #fixture_file_name"
  end

  def processor_class
    raise NotImplementedError, "#{self.class} must implement #processor_class"
  end

  def feed
    @feed ||= create(:feed)
  end

  def processor
    processor_class.new(feed, file_fixture(fixture_file_name).read)
  end

  def feed_entries
    @feed_entries ||= processor.process
  end

  def feed_entry(index)
    entry = feed_entries[index]
    entry.save!
    entry
  end
end
