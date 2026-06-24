# Proves a detected non-AI candidate can actually read a source by running the
# real loader → processor → normalizer pipeline (the same Feed stage instances
# FeedPreviewWorkflow uses) and discarding the posts. Returns a Result:
#
#   status:
#     :passed      — the source is readable: at least one sampled entry produced
#                    a valid post, or the source is empty-but-valid (a brand-new
#                    feed with no posts yet still passes)
#     :failed      — fetched fine, but nothing normalized into a valid post
#     :unreachable — couldn't fetch the source (timeout / connection / 5xx)
#   posts_found: number of sampled entries that normalized (0 = "no posts yet")
#
# The verdict is gated on parse/normalize failure, not fetch failure: a fetch
# problem says nothing about whether the profile fits the source. A single
# malformed entry doesn't fail an otherwise-working feed.
#
# AI candidates are never tested here — detection is deliberately LLM-free, and
# an AI profile matches anything — so callers mark those :not_tested without
# invoking this.
class CandidateTester
  # Normalize at most this many entries: enough to prove the profile reads the
  # source's shape without paying to normalize a whole backlog.
  SAMPLE_SIZE = 10

  Result = Data.define(:status, :posts_found)

  def initialize(user:, input:, profile_key:, http_client: nil)
    @user = user
    @input = input
    @profile_key = profile_key
    @http_client = http_client
  end

  def call
    entries = process(load)
    posts_found = entries.first(SAMPLE_SIZE).count { |entry| normalized?(entry) }
    status = entries.empty? || posts_found.positive? ? :passed : :failed
    Result.new(status: status, posts_found: posts_found)
  rescue Loader::Error => e
    Result.new(status: fetch_failure?(e) ? :unreachable : :failed, posts_found: 0)
  rescue HttpClient::Error
    Result.new(status: :unreachable, posts_found: 0)
  rescue StandardError
    Result.new(status: :failed, posts_found: 0)
  end

  private

  attr_reader :user, :input, :profile_key, :http_client

  def load
    feed.loader_instance(loader_options).load
  end

  def process(raw_data)
    feed.processor_instance(raw_data).process
  end

  # One entry's normalization. A raise means this entry can't become a valid
  # post; while probing compatibility that's an expected outcome, so it's
  # swallowed and the entry simply doesn't count toward posts_found.
  def normalized?(entry)
    normalize(entry)
    true
  rescue StandardError
    false
  end

  def normalize(entry)
    feed_entry = FeedEntry.new(
      uid: entry.uid,
      published_at: entry.published_at,
      raw_data: entry.raw_data,
      feed: feed
    )
    feed.normalizer_instance(feed_entry).normalize
  end

  # Distinguish a transient fetch problem from a deterministic incompatibility.
  # Loaders wrap transport errors (timeout/connection), so those surface as the
  # error's cause; a 5xx is transient too. Everything else a loader raises after
  # fetching fine (e.g. YouTube's "no feed link") is a real test failure, not an
  # unreachable source.
  def fetch_failure?(error)
    error.cause.is_a?(HttpClient::Error) || error.message.match?(/\bHTTP 5\d\d\b/)
  end

  # Non-AI candidates are always URL-shaped (see FeedProfile), so the source
  # input lives under the "url" param.
  def feed
    @feed ||= Feed.new(params: { "url" => input }, feed_profile_key: profile_key, user: user)
  end

  # Share the run's caching client so testing reuses the body already fetched
  # during matching instead of hitting the source again.
  def loader_options
    http_client ? { http_client: http_client } : {}
  end
end
