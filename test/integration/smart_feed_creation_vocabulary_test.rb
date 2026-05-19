require "test_helper"

# FR-022 + SC-005 vocabulary firewall: no implementation jargon in any
# user-visible string on the feed-creation surface or the AI-credentials
# pages. "AI", "AI credentials", and provider brand names are allowed.
class SmartFeedCreationVocabularyTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  BANNED_WORDS = %w[profile matcher pipeline stage loader processor normalizer LLM].freeze

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  def credential
    @credential ||= create(:llm_credential, :active, user: user)
  end

  def visible_text(body)
    # Strip script and style payloads (which may legitimately mention
    # banned words in selectors / class names) and HTML tags. Leaves
    # only what the user actually reads on screen.
    body
      .gsub(/<script\b[^>]*>.*?<\/script>/mi, "")
      .gsub(/<style\b[^>]*>.*?<\/style>/mi, "")
      .gsub(/<[^>]+>/, " ")
      .gsub(/\s+/, " ")
  end

  def assert_no_banned_vocabulary(body, page:)
    text = visible_text(body)
    BANNED_WORDS.each do |word|
      assert_no_match(
        /\b#{Regexp.escape(word)}\b/i,
        text,
        "Banned word '#{word}' appeared in user-visible text on #{page}"
      )
    end
  end

  test "#feeds_new should not leak implementation vocabulary" do
    sign_in_as(user)
    get new_feed_url
    assert_response :success
    assert_no_banned_vocabulary(response.body, page: "/feeds/new")
  end

  test "#llm_credentials_index should not leak implementation vocabulary" do
    sign_in_as(user)
    credential
    get llm_credentials_url
    assert_response :success
    assert_no_banned_vocabulary(response.body, page: "/llm_credentials")
  end

  test "#llm_credentials_new should not leak implementation vocabulary" do
    sign_in_as(user)
    get new_llm_credential_url
    assert_response :success
    assert_no_banned_vocabulary(response.body, page: "/llm_credentials/new")
  end

  test "#llm_credentials_show should not leak implementation vocabulary" do
    sign_in_as(user)
    get llm_credential_url(credential)
    assert_response :success
    assert_no_banned_vocabulary(response.body, page: "/llm_credentials/:id")
  end

  test "feed_details success response (form-expanded) should not leak implementation vocabulary" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    rss_body = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Example Feed</title>
          <item><title>Post</title><link>http://example.com/p1</link><guid>http://example.com/p1</guid></item>
        </channel>
      </rss>
    XML
    stub_request(:get, url).to_return(status: 200, body: rss_body)

    post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_no_banned_vocabulary(response.body, page: "feed_details (success / form-expanded)")
  end

  test "feed show page should not leak implementation vocabulary" do
    sign_in_as(user)
    feed = create(:feed,
                  user: user,
                  feed_profile_key: "rss",
                  params: { "url" => "http://example.com/feed.xml" })

    get feed_url(feed)
    assert_response :success
    assert_no_banned_vocabulary(response.body, page: "/feeds/:id")
  end
end
