# Proves a detected non-AI candidate can actually read a source by running the
# real loader → processor → normalizer pipeline (the same Feed stage instances
# FeedPreviewWorkflow uses) and discarding the posts. Returns a verdict:
#
#   :passed      — the pipeline ran clean, including an empty-but-valid source
#                  (a brand-new feed with no posts yet still passes)
#   :failed      — fetched fine, but processing/normalization produced nothing
#                  valid (a parse/normalize error)
#   :unreachable — couldn't fetch the source at all
#
# The verdict is gated on parse/normalize failure, not fetch failure: a fetch
# problem says nothing about whether the profile fits the source.
#
# AI candidates are never tested here — detection is deliberately LLM-free, and
# an AI profile matches anything — so callers mark those :not_tested without
# invoking this.
class CandidateTester
  # Normalize at most this many entries: enough to prove the profile reads the
  # source's shape without paying to normalize a whole backlog.
  SAMPLE_SIZE = 10

  def initialize(user:, input:, profile_key:, http_client: nil)
    @user = user
    @input = input
    @profile_key = profile_key
    @http_client = http_client
  end

  def test_status
    entries = process(load)
    entries.first(SAMPLE_SIZE).each { |entry| normalize(entry) }
    :passed
  rescue Loader::Error, HttpClient::Error
    :unreachable
  rescue StandardError
    :failed
  end

  private

  attr_reader :user, :input, :profile_key, :http_client

  def load
    feed.loader_instance(**loader_options).load
  end

  def process(raw_data)
    feed.processor_instance(raw_data).process
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
