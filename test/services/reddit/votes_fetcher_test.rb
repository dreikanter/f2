require "test_helper"

class Reddit::VotesFetcherTest < ActiveSupport::TestCase
  POST_BODY = JSON.generate([
    { "kind" => "Listing", "data" => { "children" => [
      { "kind" => "t3", "data" => {
        "id" => "1abc234",
        "title" => "Ruby 3.4 released",
        "author" => "rubydev",
        "score" => 1423,
        "ups" => 1423,
        "upvote_ratio" => 0.97,
        "num_comments" => 218,
        "permalink" => "/r/ruby/comments/1abc234/ruby_34_released/"
      } }
    ] } },
    { "kind" => "Listing", "data" => { "children" => [] } }
  ])

  LISTING_BODY = JSON.generate(
    "kind" => "Listing",
    "data" => { "children" => [
      { "kind" => "t3", "data" => { "id" => "a1", "title" => "First", "score" => 10, "ups" => 10, "upvote_ratio" => 0.9, "num_comments" => 1, "permalink" => "/r/ruby/comments/a1/first/" } },
      { "kind" => "t3", "data" => { "id" => "b2", "title" => "Second", "score" => 20, "ups" => 20, "upvote_ratio" => 0.8, "num_comments" => 2, "permalink" => "/r/ruby/comments/b2/second/" } }
    ] }
  )

  test "#post should extract vote stats from a single-post payload" do
    stats = fetcher(POST_BODY).post("https://www.reddit.com/r/ruby/comments/1abc234/ruby_34_released/")

    assert_equal "1abc234", stats.id
    assert_equal 1423, stats.score
    assert_equal 0.97, stats.upvote_ratio
    assert_equal 218, stats.num_comments
    assert_equal "https://www.reddit.com/r/ruby/comments/1abc234/ruby_34_released/", stats.permalink
  end

  test "#post should append .json to the requested URL" do
    client = stub_client(POST_BODY)
    Reddit::VotesFetcher.new(http_client: client).post("https://www.reddit.com/r/ruby/comments/1abc234/ruby_34_released/")
    assert_equal "https://www.reddit.com/r/ruby/comments/1abc234/ruby_34_released.json", client.last_url
  end

  test "#post should not double-append .json" do
    client = stub_client(POST_BODY)
    Reddit::VotesFetcher.new(http_client: client).post("https://www.reddit.com/r/ruby/comments/1abc234/x.json")
    assert_equal "https://www.reddit.com/r/ruby/comments/1abc234/x.json", client.last_url
  end

  test "#post should strip query and fragment before appending .json" do
    client = stub_client(POST_BODY)
    Reddit::VotesFetcher.new(http_client: client).post("https://www.reddit.com/r/ruby/comments/1abc234/x/?utm=1#top")
    assert_equal "https://www.reddit.com/r/ruby/comments/1abc234/x.json", client.last_url
  end

  test "#listing should return stats for every child" do
    stats = fetcher(LISTING_BODY).listing("https://www.reddit.com/r/ruby/top/")

    assert_equal %w[First Second], stats.map(&:title)
    assert_equal [10, 20], stats.map(&:score)
  end

  test "#post should raise HttpError carrying the status on a non-2xx response" do
    error = assert_raises(Reddit::VotesFetcher::HttpError) do
      fetcher("blocked", status: 403).post("https://www.reddit.com/r/ruby/comments/x/")
    end
    assert_equal 403, error.status
    assert_equal "HTTP 403", error.message
  end

  test "#post should raise when no post is present" do
    body = JSON.generate([{ "data" => { "children" => [] } }, { "data" => { "children" => [] } }])
    assert_raises(Reddit::VotesFetcher::Error) do
      fetcher(body).post("https://www.reddit.com/r/ruby/comments/x/")
    end
  end

  test "Stats#to_s should render a compact human summary" do
    stats = Reddit::VotesFetcher::Stats.new(id: "x", title: "Hi", author: "a", score: 42, ups: 42, upvote_ratio: 0.955, num_comments: 3, permalink: nil)
    assert_equal "[42 pts | 96% up | 3 comments] Hi", stats.to_s
  end

  private

  def fetcher(body, status: 200)
    Reddit::VotesFetcher.new(http_client: stub_client(body, status: status))
  end

  def stub_client(body, status: 200)
    StubClient.new(HttpClient::Response.new(status: status, body: body))
  end

  class StubClient
    attr_reader :last_url

    def initialize(response)
      @response = response
    end

    def get(url, headers: {}, options: {})
      @last_url = url
      @response
    end
  end
end
