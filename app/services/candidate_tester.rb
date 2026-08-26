# Proves a detected non-AI candidate can read a source by running the real
# loader, processor, and normalizer, then discarding the posts. Returns a
# Result whose status is a FeedIdentification::Candidate verdict: PASSED
# (readable, or empty but recognized), FAILED (fetched but not readable as
# this profile), UNREACHABLE (couldn't fetch). posts_found counts sampled
# entries that normalized.
#
# The verdict gates on parse failure, not fetch failure: a fetch problem
# says nothing about whether the profile fits. AI candidates never come
# here; detection is LLM-free.
class CandidateTester
  Candidate = FeedIdentification::Candidate

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
    result = feed.processor_instance(load).process
    posts_found = result.entries.first(SAMPLE_SIZE).count { |entry| normalized?(entry) }
    Result.new(status: verdict(result, posts_found), posts_found: posts_found)
  rescue Loader::Error => e
    # Loaders wrap transport errors, so a transient failure shows up as the
    # cause. Any other Loader::Error means we fetched but couldn't read.
    Result.new(status: e.cause.is_a?(HttpClient::Error) ? Candidate::UNREACHABLE : Candidate::FAILED, posts_found: 0)
  rescue StandardError
    Result.new(status: Candidate::FAILED, posts_found: 0)
  end

  private

  attr_reader :user, :input, :profile_key, :http_client

  def load
    feed.loader_instance(loader_options).load
  end

  # An empty result passes only if the processor recognized the payload —
  # otherwise the page was unreadable, not empty-but-valid.
  def verdict(result, posts_found)
    return Candidate::PASSED if posts_found.positive?
    return Candidate::PASSED if result.entries.empty? && result.recognized?

    Candidate::FAILED
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
