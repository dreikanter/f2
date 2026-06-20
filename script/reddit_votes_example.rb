# Ad-hoc PoC runner for Reddit::VotesFetcher.
#
#   bin/rails runner script/reddit_votes_example.rb
#   bin/rails runner script/reddit_votes_example.rb https://www.reddit.com/r/ruby/comments/.../
#
# With no argument it hits a few random posts via a subreddit listing. If the
# network blocks Reddit (e.g. egress policy, datacenter-IP block), it falls back
# to a bundled sample payload so the parsing path still runs end to end.

fetcher = Reddit::VotesFetcher.new

def show(stats)
  Array(stats).each do |s|
    puts "  #{s}"
    puts "    #{s.permalink}"
  end
end

url = ARGV[0]

begin
  if url
    puts "Fetching single post: #{url}"
    show(fetcher.post(url))
  else
    listing_url = "https://www.reddit.com/r/ruby/top/?t=year"
    puts "Fetching listing: #{listing_url}"
    show(fetcher.listing(listing_url))
  end
rescue Reddit::VotesFetcher::Error => e
  warn "Live fetch failed: #{e.message}"
  warn "Falling back to bundled sample payload to exercise parsing...\n\n"

  sample = JSON.parse(File.read(Rails.root.join("script/fixtures/reddit_post.json")))
  stub = Class.new do
    def initialize(body) = @body = body
    def get(*) = HttpClient::Response.new(status: 200, body: @body)
  end.new(JSON.generate(sample))

  show(Reddit::VotesFetcher.new(http_client: stub).post("https://www.reddit.com/r/ruby/comments/sample/"))
end
