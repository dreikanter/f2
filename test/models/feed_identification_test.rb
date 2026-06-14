require "test_helper"

class FeedIdentificationTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  test "should default candidates to an empty array" do
    identification = FeedIdentification.new(user: user, input: "https://example.com/feed.xml")
    assert_equal [], identification.candidates
  end

  test "should persist candidates as JSONB" do
    identification = FeedIdentification.create!(
      user: user,
      input: "https://example.com/feed.xml",
      status: :success,
      candidates: [
        { "profile_key" => "rss", "rank" => 0, "depends_on_ai" => false, "title" => "Sample Feed" }
      ]
    )

    identification.reload

    assert_equal 1, identification.candidates.size
    assert_equal "rss", identification.candidates.first["profile_key"]
    assert_equal 0, identification.candidates.first["rank"]
    assert_equal false, identification.candidates.first["depends_on_ai"]
  end

  test "#invalid_processing? should be true when processing without started_at" do
    identification = FeedIdentification.new(user: user, input: "https://example.com/feed.xml", status: :processing, started_at: nil)
    assert_predicate identification, :invalid_processing?
  end

  test "#invalid_processing? should be false when started_at is present" do
    identification = FeedIdentification.new(user: user, input: "https://example.com/feed.xml", status: :processing, started_at: Time.current)
    refute_predicate identification, :invalid_processing?
  end

  test "#invalid_processing? should be false for non-processing status" do
    identification = FeedIdentification.new(user: user, input: "https://example.com/feed.xml", status: :success, started_at: nil)
    refute_predicate identification, :invalid_processing?
  end

  test "#timed_out? should be true when processing exceeds the identification timeout" do
    identification = FeedIdentification.new(
      user: user,
      input: "https://example.com/feed.xml",
      status: :processing,
      started_at: (FeedIdentification::IDENTIFICATION_TIMEOUT_SECONDS + 1).seconds.ago
    )
    assert_predicate identification, :timed_out?
  end

  test "#timed_out? should be false within the identification timeout" do
    identification = FeedIdentification.new(
      user: user,
      input: "https://example.com/feed.xml",
      status: :processing,
      started_at: 1.second.ago
    )
    refute_predicate identification, :timed_out?
  end

  test "#timed_out? should be false when started_at is missing" do
    identification = FeedIdentification.new(user: user, input: "https://example.com/feed.xml", status: :processing, started_at: nil)
    refute_predicate identification, :timed_out?
  end

  test "#timed_out? should be false for non-processing status" do
    identification = FeedIdentification.new(
      user: user,
      input: "https://example.com/feed.xml",
      status: :success,
      started_at: 1.hour.ago
    )
    refute_predicate identification, :timed_out?
  end

  test "POLLING_MAX_POLLS should keep the client polling past the server timeout" do
    client_coverage_ms = FeedIdentification::POLLING_MAX_POLLS * StatePolling::POLLING_INTERVAL_MS

    assert_operator(
      client_coverage_ms, :>, FeedIdentification::IDENTIFICATION_TIMEOUT_SECONDS * 1000,
      "client must outlast the server timeout so the friendly error renders before it gives up"
    )
  end

  test "should accept multiple ranked candidates" do
    identification = FeedIdentification.create!(
      user: user,
      input: "https://example.com/article",
      status: :success,
      candidates: [
        { "profile_key" => "rss", "rank" => 0, "depends_on_ai" => false },
        { "profile_key" => "llm_website_extractor", "rank" => 1, "depends_on_ai" => true }
      ]
    )

    identification.reload

    assert_equal %w[rss llm_website_extractor], identification.candidates.map { |c| c["profile_key"] }
  end
end
