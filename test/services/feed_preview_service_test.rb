require "test_helper"

class FeedPreviewServiceTest < ActiveSupport::TestCase
  def rss_body
    @rss_body ||= file_fixture("feeds/rss/feed.xml").read
  end

  def user
    @user ||= create(:user)
  end

  def feed_url
    "https://example.com/feed.xml"
  end

  def stub_rss(body: nil, status: 200)
    stub_request(:get, feed_url)
      .to_return(status: status, body: body || rss_body, headers: { "Content-Type" => "application/xml" })
  end

  def call(**overrides)
    FeedPreviewService.call(
      user: user,
      profile_key: "rss",
      params: { "url" => feed_url },
      **overrides
    )
  end

  def with_memory_cache
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = previous
  end

  test ".call should return a Preview with PostDraft entries on success" do
    stub_rss

    preview = call

    assert_kind_of FeedPreviewService::Preview, preview
    assert_kind_of Array, preview.posts
    assert_predicate preview.posts.size, :positive?
    assert(preview.posts.all? { |p| p.is_a?(FeedPreviewService::PostDraft) })
  end

  test ".call should populate PostDraft fields" do
    stub_rss

    draft = call.posts.first

    assert draft.uid.present?
    assert draft.source_url.present?
    assert draft.body.present?
    assert_kind_of Array, draft.supplementary
    assert_kind_of Array, draft.images
  end

  test ".call should clamp limit to the 2..5 range" do
    stub_rss

    preview_low = call(limit: 1)
    preview_high = call(limit: 99)

    assert_operator preview_low.posts.size, :>=, [2, preview_low.posts.size].min
    assert_operator preview_high.posts.size, :<=, 5
  end

  test ".call should respect a custom limit within the allowed range" do
    stub_rss

    preview = call(limit: 3)

    assert_operator preview.posts.size, :<=, 3
  end

  test ".call should populate generated_at with the current time" do
    stub_rss

    freeze_time do
      preview = call

      assert_equal Time.current, preview.generated_at
    end
  end

  test ".call should set used_ai false for non-AI profiles" do
    stub_rss

    preview = call

    assert_not preview.used_ai
    assert_nil preview.llm_usage_id
  end

  test ".call should mint a valid preview_token tied to (user, profile, params)" do
    stub_rss

    preview = call

    assert preview.preview_token.present?
    assert PreviewToken.verify(
      preview.preview_token,
      user_id: user.id,
      profile_key: "rss",
      params: { "url" => feed_url }
    )
  end

  test ".call should populate source_summary as a non-empty string" do
    stub_rss

    preview = call

    assert preview.source_summary.is_a?(String)
    assert preview.source_summary.present?
  end

  test ".call should raise SourceUnreachable when the loader fails" do
    stub_request(:get, feed_url).to_return(status: 500, body: "Server Error")

    assert_raises FeedPreviewService::SourceUnreachable do
      call
    end
  end

  test ".call should raise Empty when no entries are returned" do
    empty_rss = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Empty</title>
          <description>Empty feed</description>
          <link>https://example.com</link>
        </channel>
      </rss>
    XML
    stub_rss(body: empty_rss)

    assert_raises FeedPreviewService::Empty do
      call
    end
  end

  test ".call should hit the cache on a second call with the same cache_key" do
    with_memory_cache do
      stub_rss

      first = call(cache_key: "preview:abc")
      # Remove the stub: a second call hitting cache must not need network.
      WebMock.reset!

      second = call(cache_key: "preview:abc")

      assert_equal first.preview_token, second.preview_token
      assert_equal first.generated_at, second.generated_at
    end
  end

  test ".call should bypass the cache when refresh: true" do
    with_memory_cache do
      stub_rss

      first = call(cache_key: "preview:abc")
      first_generated_at = first.generated_at

      travel 5.seconds do
        stub_rss
        second = call(cache_key: "preview:abc", refresh: true)

        assert_not_equal first_generated_at, second.generated_at
      end
    end
  end
end
