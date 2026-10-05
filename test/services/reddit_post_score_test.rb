require "test_helper"

class RedditPostScoreTest < ActiveSupport::TestCase
  include CacheTestHelpers

  FIRST = "https://first.example"
  SECOND = "https://second.example"
  POST_URL = "#{FIRST}/comments/92dd8/"

  test "#call should return the full score for a Reddit URL" do
    stub_request(:get, POST_URL).to_return(body: post_page)

    assert_equal 21871, score("https://www.reddit.com/r/reddit.com/comments/92dd8/test_post_please_ignore/?share=1")
  end

  test "#call should accept a post ID and fullname" do
    stub_request(:get, POST_URL).to_return(body: post_page)

    assert_equal 21871, score("92dd8")
    assert_equal 21871, score("t3_92dd8")
  end

  test "#call should accept short links and permalink paths" do
    stub_request(:get, POST_URL).to_return(body: post_page)

    assert_equal 21871, score("https://redd.it/92dd8?share=1")
    assert_equal 21871, score("/comments/92dd8/")
  end

  test "#call should discard Unicode slugs and comment references" do
    stub_request(:get, POST_URL).to_return(body: post_page)

    assert_equal 21871, score("https://old.reddit.com/r/test/comments/92dd8/тест/abc123/?context=3")
  end

  test "#call should preserve a genuine zero score" do
    stub_request(:get, POST_URL).to_return(body: post_page.sub('title="21871"', 'title="0"'))

    assert_equal 0, score
  end

  test "#call should preserve a negative score" do
    stub_request(:get, POST_URL).to_return(body: post_page.sub('title="21871"', 'title="-12"'))

    assert_equal(-12, score)
  end

  test "#call should fall back after an HTTP error" do
    stub_request(:get, POST_URL).to_return(status: 429)
    stub_request(:get, "#{SECOND}/comments/92dd8/").to_return(body: post_page)

    assert_equal 21871, score(instances: [FIRST, SECOND])
    assert_requested :get, POST_URL
  end

  test "#call should fall back after a timeout" do
    stub_request(:get, POST_URL).to_timeout
    stub_request(:get, "#{SECOND}/comments/92dd8/").to_return(body: post_page)

    assert_equal 21871, score(instances: [FIRST, SECOND])
    assert_requested :get, POST_URL
  end

  test "#call should fall back after a successful challenge page" do
    stub_request(:get, POST_URL).to_return(body: "<html><title>Making sure you're not a bot!</title></html>")
    stub_request(:get, "#{SECOND}/comments/92dd8/").to_return(body: post_page)

    assert_equal 21871, score(instances: [FIRST, SECOND])
    assert_requested :get, POST_URL
  end

  test "#call should reject a score belonging to another post" do
    stub_request(:get, POST_URL).to_return(body: post_page.sub("comments/92dd8/", "comments/abc123/"))

    assert_raises(RedditPostScore::UnavailableError) { score }
  end

  test "#call should reject hidden and malformed scores" do
    stub_request(:get, POST_URL).to_return(body: post_page.sub('title="21871"', 'title="•"'))
                               .then.to_return(body: post_page.sub('title="21871"', 'title="21.9k"'))

    assert_raises(RedditPostScore::UnavailableError) { score }
    assert_raises(RedditPostScore::UnavailableError) { score }
  end

  test "#call should stop after a successful lookup" do
    stub_request(:get, POST_URL).to_return(body: post_page)

    assert_equal 21871, score(instances: [FIRST, SECOND])
    assert_not_requested :get, "#{SECOND}/comments/92dd8/"
  end

  test "#call should raise when no instances are available" do
    assert_raises(RedditPostScore::UnavailableError) { score(instances: []) }
    assert_not_requested :get, /./
  end

  test "#call should reject invalid references before discovery" do
    assert_raises(ArgumentError) { score("https://reddit.com.evil.example/comments/92dd8/", instances: nil) }
    assert_raises(ArgumentError) { score("https://reddit.com/r/ruby/", instances: nil) }
    assert_raises(ArgumentError) { score(nil, instances: nil) }
    assert_not_requested :get, /./
  end

  test "#call should discover instances by default" do
    stub_request(:get, RedlibInstances::SOURCE_URL).to_return(body: { instances: [{ url: FIRST }] }.to_json)
    stub_request(:get, POST_URL).to_return(body: post_page)

    with_memory_cache do
      assert_equal 21871, score(instances: nil)
    end
  end

  test "#call should expose directory failures as unavailable scores" do
    stub_request(:get, RedlibInstances::SOURCE_URL).to_return(status: 503)

    with_memory_cache do
      assert_raises(RedditPostScore::UnavailableError) { score(instances: nil) }
    end
  end

  test "#call should block redirects to private addresses" do
    stub_request(:get, POST_URL).to_return(status: 302, headers: { "Location" => "http://127.0.0.1/private" })

    assert_raises(RedditPostScore::UnavailableError) { score }
    assert_not_requested :get, "http://127.0.0.1/private"
  end

  private

  def post_page
    file_fixture("reddit_post_score.html").read
  end

  def score(reference = "92dd8", instances: [FIRST])
    Socket.stub(:getaddrinfo, [[nil, nil, nil, "93.184.216.34"]]) do
      RedditPostScore.new(instances: instances).call(reference)
    end
  end
end
