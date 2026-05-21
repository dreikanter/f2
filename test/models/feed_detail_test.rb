require "test_helper"

class FeedDetailTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  test "should default candidates to an empty array" do
    detail = FeedDetail.new(user: user, url: "https://example.com/feed.xml")
    assert_equal [], detail.candidates
  end

  test "should persist candidates as JSONB" do
    detail = FeedDetail.create!(
      user: user,
      url: "https://example.com/feed.xml",
      status: :success,
      candidates: [
        { "profile_key" => "rss", "rank" => 0, "depends_on_ai" => false, "title" => "Sample Feed" }
      ]
    )

    detail.reload

    assert_equal 1, detail.candidates.size
    assert_equal "rss", detail.candidates.first["profile_key"]
    assert_equal 0, detail.candidates.first["rank"]
    assert_equal false, detail.candidates.first["depends_on_ai"]
  end

  test "#invalid_processing? should be true when processing without started_at" do
    detail = FeedDetail.new(user: user, url: "https://example.com/feed.xml", status: :processing, started_at: nil)
    assert_predicate detail, :invalid_processing?
  end

  test "#invalid_processing? should be false when started_at is present" do
    detail = FeedDetail.new(user: user, url: "https://example.com/feed.xml", status: :processing, started_at: Time.current)
    refute_predicate detail, :invalid_processing?
  end

  test "#invalid_processing? should be false for non-processing status" do
    detail = FeedDetail.new(user: user, url: "https://example.com/feed.xml", status: :success, started_at: nil)
    refute_predicate detail, :invalid_processing?
  end

  test "#timed_out? should be true when processing exceeds the identification timeout" do
    detail = FeedDetail.new(
      user: user,
      url: "https://example.com/feed.xml",
      status: :processing,
      started_at: (FeedDetail::IDENTIFICATION_TIMEOUT_SECONDS + 1).seconds.ago
    )
    assert_predicate detail, :timed_out?
  end

  test "#timed_out? should be false within the identification timeout" do
    detail = FeedDetail.new(
      user: user,
      url: "https://example.com/feed.xml",
      status: :processing,
      started_at: 1.second.ago
    )
    refute_predicate detail, :timed_out?
  end

  test "#timed_out? should be false when started_at is missing" do
    detail = FeedDetail.new(user: user, url: "https://example.com/feed.xml", status: :processing, started_at: nil)
    refute_predicate detail, :timed_out?
  end

  test "#timed_out? should be false for non-processing status" do
    detail = FeedDetail.new(
      user: user,
      url: "https://example.com/feed.xml",
      status: :success,
      started_at: 1.hour.ago
    )
    refute_predicate detail, :timed_out?
  end

  test "should accept multiple ranked candidates" do
    detail = FeedDetail.create!(
      user: user,
      url: "https://example.com/article",
      status: :success,
      candidates: [
        { "profile_key" => "rss", "rank" => 0, "depends_on_ai" => false },
        { "profile_key" => "llm_website_extractor", "rank" => 1, "depends_on_ai" => true }
      ]
    )

    detail.reload

    assert_equal %w[rss llm_website_extractor], detail.candidates.map { |c| c["profile_key"] }
  end
end
