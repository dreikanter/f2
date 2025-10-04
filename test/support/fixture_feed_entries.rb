module FixtureFeedEntries
  def fixture_dir
    raise NotImplementedError, "#{self.class} must implement #fixture_dir"
  end

  def processor_class
    raise NotImplementedError, "#{self.class} must implement #processor_class"
  end

  def feed
    @feed ||= create(:feed)
  end

  def processor
    feed_xml = File.read(Rails.root.join("test/fixtures", fixture_dir, "feed.xml"))
    processor_class.new(feed, feed_xml)
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
