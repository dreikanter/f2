require "test_helper"
require_relative "../../db/migrate/20261107120000_replace_rss_comment_option"

class ReplaceRssCommentOptionTest < ActiveSupport::TestCase
  test "#up should map legacy RSS options and preserve other params" do
    feeds = [true, false, nil].map do |value|
      feed = create(:feed)
      params = { "url" => "https://example.com/feed", "max_comments" => 3 }
      params["content_in_comments"] = value unless value.nil?
      feed.update_columns(params: params)
      feed
    end
    other = create(:feed, feed_profile_key: "youtube", params: { "url" => "https://example.com" })
    migration = ReplaceRssCommentOption.new

    migration.migrate(:up)

    assert_equal %w[text_in_comment title_and_text title_and_text], feeds.map { |feed| feed.reload.params["article_presentation"] }
    feeds.each do |feed|
      assert_not feed.params.key?("content_in_comments")
      assert_equal 3, feed.params["max_comments"]
      assert_equal "https://example.com/feed", feed.params["url"]
    end
    assert_not other.reload.params.key?("article_presentation")

    migration.migrate(:down)

    assert_equal [true, false, false], feeds.map { |feed| feed.reload.params["content_in_comments"] }
    feeds.each { |feed| assert_not feed.params.key?("article_presentation") }
  end
end
