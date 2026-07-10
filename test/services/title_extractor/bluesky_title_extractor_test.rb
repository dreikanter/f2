require "test_helper"

class TitleExtractor::BlueskyTitleExtractorTest < ActiveSupport::TestCase
  def extractor(input, body = nil)
    TitleExtractor::BlueskyTitleExtractor.new(input, body)
  end

  test "#title should use the og:title from the fetched page" do
    body = '<html><head><meta property="og:title" content="Test User (@testuser.bsky.social)"></head></html>'
    assert_equal "Test User (@testuser.bsky.social)", extractor("https://bsky.app/profile/testuser.bsky.social", body).title
  end

  test "#title should fall back to the @handle from a profile URL" do
    assert_equal "@testuser.bsky.social", extractor("https://bsky.app/profile/testuser.bsky.social").title
  end

  test "#title should ignore extra path segments in the fallback" do
    assert_equal "@testuser.bsky.social", extractor("https://bsky.app/profile/testuser.bsky.social/post/3aaa").title
  end
end
