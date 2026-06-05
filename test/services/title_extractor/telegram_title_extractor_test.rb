require "test_helper"

class TitleExtractor::TelegramTitleExtractorTest < ActiveSupport::TestCase
  def extractor(input, body = nil)
    TitleExtractor::TelegramTitleExtractor.new(input, body)
  end

  test "#title should use the og:title from the fetched page" do
    body = file_fixture("feeds/telegram/channel.html").read
    assert_equal "Test Channel", extractor("https://t.me/testchannel", body).title
  end

  test "#title should fall back to the username from a full URL" do
    assert_equal "durov", extractor("https://t.me/durov").title
  end

  test "#title should fall back to the username from an @handle" do
    assert_equal "durov", extractor("@durov").title
  end

  test "#title should fall back to a bare username" do
    assert_equal "durov", extractor("durov").title
  end

  test "#title should ignore a blank fetched body" do
    assert_equal "durov", extractor("https://t.me/durov", "").title
  end
end
