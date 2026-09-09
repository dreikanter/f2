require "test_helper"

class ComicFeedMigrationTest < ActiveSupport::TestCase
  CASES = JSON.parse(File.read(Rails.root.join("test/fixtures/files/feeds/comic_migration.json"))).freeze

  CASES.each do |profile_key, sample|
    test "#{profile_key} pipeline should preserve the audited comic content" do
      feed = create(:feed, feed_profile_key: profile_key, url: sample.fetch("feed_url"))
      xml = file_fixture("feeds/#{profile_key}/current.xml").read
      stub_request(:get, feed.url).to_return(body: xml)
      sample.fetch("pages").each do |page|
        body = page["file"] ? file_fixture("feeds/#{page['file']}").read : ""
        stub_request(:get, page.fetch("url")).to_return(status: page.fetch("status"), body: body)
      end

      entries = feed.processor_instance(feed.loader_instance.load).process.entries
      posts = entries.map { |entry| feed.normalizer_instance(entry).normalize }

      assert_equal sample.fetch("entries").size, posts.size
      posts.zip(sample.fetch("entries")).each do |post, expected|
        assert_equal expected.fetch("uid"), post.uid
        assert_equal expected.fetch("text"), post.content, post.uid
        assert_equal expected.fetch("attachments"), post.attachment_urls, post.uid
        assert_equal expected.fetch("comments"), post.comments, post.uid
        assert_equal Time.iso8601(expected.fetch("published_at")), post.published_at, post.uid
        assert_equal expected.fetch("validation_errors"), post.validation_errors, post.uid
        assert post.enqueued?, post.uid
      end
    end
  end
end
