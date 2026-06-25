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


  def identification(candidates)
    FeedIdentification.new(user: user, input: "https://example.com/feed.xml", candidates: candidates)
  end

  test "#recommended_candidate should prefer a passed candidate over a failed one ranked ahead of it" do
    id = identification([
      { "profile_key" => "rss", "test_status" => "failed" },
      { "profile_key" => "atom", "test_status" => "passed" }
    ])

    assert_equal "atom", id.recommended_candidate["profile_key"]
  end

  test "#recommended_candidate should prefer passed over not_tested and unreachable" do
    id = identification([
      { "profile_key" => "youtube", "test_status" => "unreachable" },
      { "profile_key" => "llm_website_extractor", "test_status" => "not_tested" },
      { "profile_key" => "rss", "test_status" => "passed" }
    ])

    assert_equal "rss", id.recommended_candidate["profile_key"]
  end

  test "#recommended_candidate should fall back to the AI option when every structured candidate failed" do
    id = identification([
      { "profile_key" => "rss", "test_status" => "failed" },
      { "profile_key" => "llm_website_extractor", "test_status" => "not_tested" }
    ])

    assert_equal "llm_website_extractor", id.recommended_candidate["profile_key"]
  end

  test "#recommended_candidate should prefer the AI option over an unreachable source" do
    id = identification([
      { "profile_key" => "youtube", "test_status" => "unreachable" },
      { "profile_key" => "llm_website_extractor", "test_status" => "not_tested" }
    ])

    assert_equal "llm_website_extractor", id.recommended_candidate["profile_key"]
  end

  test "#recommended_candidate should never preselect a failed candidate" do
    id = identification([
      { "profile_key" => "rss", "test_status" => "failed" },
      { "profile_key" => "youtube", "test_status" => "unreachable" }
    ])

    assert_equal "youtube", id.recommended_candidate["profile_key"]
  end

  test "#recommended_candidate should fall back to the first candidate when none carry a verdict" do
    id = identification([
      { "profile_key" => "rss" },
      { "profile_key" => "llm_website_extractor" }
    ])

    assert_equal "rss", id.recommended_candidate["profile_key"]
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
