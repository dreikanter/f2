require "test_helper"

class RedditRetrievalProbeTest < ActiveSupport::TestCase
  def stats(score:, permalink: "https://www.reddit.com/r/programming/comments/x/t/", num_comments: 5)
    Reddit::VotesFetcher::Stats.new(id: "x", title: "T", author: "a", score: score, ups: score,
                                    upvote_ratio: 0.9, num_comments: num_comments, permalink: permalink)
  end

  test "should report PASS across checks when the JSON API is reachable" do
    fetcher = FakeFetcher.new(listing: [stats(score: 100), stats(score: 50)], post: stats(score: 100))
    http = FakeHttp.new(200)

    outcome = RedditRetrievalProbe.run(fetcher: fetcher, http_client: http)

    assert outcome[:passed]
    assert_equal %w[listing single_post old_reddit rss_control], outcome[:results].map { |r| r[:check] }
    assert_equal %w[PASS PASS PASS PASS], outcome[:results].map { |r| r[:status] }
  end

  test "single_post should follow the first permalink from the listing" do
    fetcher = FakeFetcher.new(listing: [stats(score: 100, permalink: "https://www.reddit.com/r/programming/comments/abc/t/")], post: stats(score: 100))
    RedditRetrievalProbe.run(fetcher: fetcher, http_client: FakeHttp.new(200))

    assert_equal "https://www.reddit.com/r/programming/comments/abc/t/", fetcher.requested_post_url
  end

  test "single_post should SKIP when the listing yields no permalink" do
    fetcher = FakeFetcher.new(listing: [], post: stats(score: 1))
    outcome = RedditRetrievalProbe.run(fetcher: fetcher, http_client: FakeHttp.new(200), checks: %w[listing single_post])

    single = outcome[:results].find { |r| r[:check] == "single_post" }
    assert_equal "SKIP", single[:status]
    assert_nil fetcher.requested_post_url
  end

  test "listing should FAIL when no post carries a numeric score" do
    fetcher = FakeFetcher.new(listing: [stats(score: nil)], post: stats(score: 1))
    outcome = RedditRetrievalProbe.run(fetcher: fetcher, http_client: FakeHttp.new(200), checks: %w[listing])

    assert_equal "FAIL", outcome[:results].first[:status]
    assert_not outcome[:passed]
  end

  test "a check should record FAIL instead of raising when the fetcher errors" do
    fetcher = FakeFetcher.new(listing: Reddit::VotesFetcher::HttpError.new(403), post: stats(score: 1))
    outcome = RedditRetrievalProbe.run(fetcher: fetcher, http_client: FakeHttp.new(200), checks: %w[listing])

    result = outcome[:results].first
    assert_equal "FAIL", result[:status]
    assert_includes result[:note], "403"
  end

  test "rss_control and old_reddit should reflect raw HTTP status" do
    fetcher = FakeFetcher.new(listing: [stats(score: 1)], post: stats(score: 1))
    outcome = RedditRetrievalProbe.run(fetcher: fetcher, http_client: FakeHttp.new(403), checks: %w[old_reddit rss_control])

    assert_equal %w[FAIL FAIL], outcome[:results].map { |r| r[:status] }
    assert(outcome[:results].all? { |r| r[:note].include?("403") })
  end

  class FakeFetcher
    attr_reader :requested_post_url

    def initialize(listing:, post:)
      @listing = listing
      @post = post
    end

    def listing(_url)
      raise @listing if @listing.is_a?(StandardError)

      @listing
    end

    def post(url)
      @requested_post_url = url
      raise @post if @post.is_a?(StandardError)

      @post
    end
  end

  class FakeHttp
    def initialize(status)
      @status = status
    end

    def get(_url, headers: {})
      HttpClient::Response.new(status: @status, body: "")
    end
  end
end
