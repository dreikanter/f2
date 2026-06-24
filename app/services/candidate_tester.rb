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
  rescue HttpClient::Error
    Result.new(status: :unreachable, posts_found: 0)
  rescue Loader::Error => e
    # A wrapped transport error (timeout/connection) is transient → unreachable.
    # Any other Loader::Error means we fetched but couldn't read the source
    # (bad status, no feed link, …) → a real failure.
    Result.new(status: e.cause.is_a?(HttpClient::Error) ? :unreachable : :failed, posts_found: 0)
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

  # Whether one entry yields a publishable post. The normalizer raises on a
  # structurally broken entry, and returns a :rejected post when content/URL
  # validation fails; only an :enqueued post counts as a real post. Both
  # failures are expected while probing compatibility, so they're swallowed.
  def normalized?(entry)
    normalize(entry).enqueued?
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
