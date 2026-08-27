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
      status: :working,
      candidates: [
        { "profile_key" => "rss", "title" => "Sample Feed" }
      ]
    )

    identification.reload

    assert_equal 1, identification.candidates.size
    assert_equal "rss", identification.candidates.first["profile_key"]
    assert_equal "Sample Feed", identification.candidates.first["title"]
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
    identification = FeedIdentification.new(user: user, input: "https://example.com/feed.xml", status: :working, started_at: nil)
    refute_predicate identification, :invalid_processing?
  end

  test "#restart_detection! should reset the row to a fresh in-flight detection" do
    identification = create(:feed_identification, :no_feed, user: user)

    assert identification.restart_detection!

    identification.reload
    assert_predicate identification, :processing?
    assert_not_nil identification.started_at
    assert_equal [], identification.candidates
  end

  test "#restart_detection! should return false after losing the insert race" do
    winner = create(:feed_identification, user: user, started_at: Time.current).reload
    # The loser's stale lookup result: it missed the winner's row, so its
    # insert collides with the user+input unique index.
    loser = FeedIdentification.new(user: user, input: winner.input)

    assert_not loser.restart_detection!
    assert_predicate loser, :new_record?
    assert_equal winner.started_at, winner.reload.started_at, "the winner's detection should not be restarted"
  end


  def identification(candidates)
    FeedIdentification.new(user: user, input: "https://example.com/feed.xml", candidates: candidates)
  end

  test "#suggested_candidate should be the highest-ranked working candidate" do
    id = identification([
      { "profile_key" => "rss", "test_status" => "failed" },
      { "profile_key" => "atom", "test_status" => "passed" }
    ])

    assert_equal "atom", id.suggested_candidate.profile_key
  end

  test "#suggested_candidate should skip failed and unreachable candidates" do
    id = identification([
      { "profile_key" => "youtube", "test_status" => "unreachable" },
      { "profile_key" => "rss", "test_status" => "failed" },
      { "profile_key" => "atom", "test_status" => "passed" }
    ])

    assert_equal "atom", id.suggested_candidate.profile_key
  end

  test "#suggested_candidate should be nil when no candidate works" do
    id = identification([
      { "profile_key" => "rss", "test_status" => "failed" },
      { "profile_key" => "youtube", "test_status" => "unreachable" }
    ])

    assert_nil id.suggested_candidate
  end

  test "#suggested_candidate should fall back to the first candidate when none carry a verdict" do
    id = identification([
      { "profile_key" => "rss" },
      { "profile_key" => "atom" }
    ])

    assert_equal "rss", id.suggested_candidate.profile_key
  end

  test "#working_candidates should exclude failed and unreachable candidates" do
    id = identification([
      { "profile_key" => "rss", "test_status" => "passed" },
      { "profile_key" => "atom", "test_status" => "failed" },
      { "profile_key" => "youtube", "test_status" => "unreachable" }
    ])

    assert_equal ["rss"], id.working_candidates.map(&:profile_key)
  end

  test "should accept multiple ranked candidates" do
    identification = FeedIdentification.create!(
      user: user,
      input: "https://example.com/article",
      status: :working,
      candidates: [
        { "profile_key" => "rss" },
        { "profile_key" => "llm" }
      ]
    )

    identification.reload

    assert_equal %w[rss llm], identification.candidates.map { |c| c["profile_key"] }
  end

  test "#working_candidate_profile_keys should list only candidates that read the source" do
    identification = FeedIdentification.new(
      status: :working,
      candidates: [
        { "profile_key" => "rss", "test_status" => "passed" },
        { "profile_key" => "atom", "test_status" => "failed" },
        { "profile_key" => "xkcd", "test_status" => "unreachable" }
      ]
    )

    assert_equal %w[rss], identification.working_candidate_profile_keys
  end

  test "#source_url_for should prefer the working candidate's discovered feed URL" do
    identification = FeedIdentification.new(
      input: "https://example.com/blog",
      status: :working,
      candidates: [
        { "profile_key" => "rss", "test_status" => "failed", "resolved_url" => "https://example.com/broken.xml" },
        { "profile_key" => "rss", "test_status" => "passed", "resolved_url" => "https://example.com/feed.xml" }
      ]
    )

    assert_equal "https://example.com/feed.xml", identification.source_url_for("rss")
  end

  test "#source_url_for should fall back to the input for direct candidates" do
    identification = FeedIdentification.new(
      input: "https://example.com/feed.xml",
      status: :working,
      candidates: [{ "profile_key" => "rss", "test_status" => "passed" }]
    )

    assert_equal "https://example.com/feed.xml", identification.source_url_for("rss")
    assert_equal "https://example.com/feed.xml", identification.source_url_for("json_feed")
  end

  test ".cleanup_for_source should destroy the row keyed by the URL" do
    identification = create(:feed_identification, user: user, input: "https://example.com/feed.xml")

    FeedIdentification.cleanup_for_source(user: user, url: "https://example.com/feed.xml")

    assert_not FeedIdentification.exists?(identification.id)
  end

  test ".cleanup_for_source should destroy the page row that resolved to the URL" do
    identification = create(
      :feed_identification,
      user: user,
      input: "https://example.com/blog",
      status: :working,
      candidates: [
        { "profile_key" => "rss", "test_status" => "passed", "resolved_url" => "https://example.com/feed.xml" }
      ]
    )

    FeedIdentification.cleanup_for_source(user: user, url: "https://example.com/feed.xml")

    assert_not FeedIdentification.exists?(identification.id)
  end

  test ".working_for_source should prefer a working page identification over a stale keyed row" do
    stale = create(:feed_identification, user: user, input: "https://example.com/feed.xml",
                                         status: :unreachable)
    page = create(
      :feed_identification,
      user: user,
      input: "https://example.com/blog",
      status: :working,
      candidates: [
        { "profile_key" => "rss", "test_status" => "passed", "resolved_url" => "https://example.com/feed.xml" }
      ]
    )

    assert_equal page, FeedIdentification.working_for_source(user: user, url: "https://example.com/feed.xml")
  end

  test ".cleanup_for_source should destroy both the keyed row and the resolving page row" do
    stale = create(:feed_identification, user: user, input: "https://example.com/feed.xml",
                                         status: :unreachable)
    page = create(
      :feed_identification,
      user: user,
      input: "https://example.com/blog",
      status: :working,
      candidates: [
        { "profile_key" => "rss", "test_status" => "passed", "resolved_url" => "https://example.com/feed.xml" }
      ]
    )

    FeedIdentification.cleanup_for_source(user: user, url: "https://example.com/feed.xml")

    assert_not FeedIdentification.exists?(stale.id)
    assert_not FeedIdentification.exists?(page.id)
  end

  test ".working_for_source should return nothing when no identification works" do
    create(:feed_identification, user: user, input: "https://example.com/feed.xml",
                                 status: :unreachable)

    assert_nil FeedIdentification.working_for_source(user: user, url: "https://example.com/feed.xml")
    assert_nil FeedIdentification.working_for_source(user: user, url: nil)
  end

  test ".cleanup_for_source should spare other users' rows and non-working candidates" do
    create(
      :feed_identification,
      user: create(:user),
      input: "https://example.com/blog",
      status: :working,
      candidates: [
        { "profile_key" => "rss", "test_status" => "passed", "resolved_url" => "https://example.com/feed.xml" }
      ]
    )
    # A working page row whose *other* candidate resolved to the URL but never
    # read it: only the candidate-level filter keeps this from matching.
    create(
      :feed_identification,
      user: user,
      input: "https://example.com/other",
      status: :working,
      candidates: [
        { "profile_key" => "atom", "test_status" => "passed", "resolved_url" => "https://example.com/other.xml" },
        { "profile_key" => "rss", "test_status" => "failed", "resolved_url" => "https://example.com/feed.xml" }
      ]
    )

    assert_no_difference("FeedIdentification.count") do
      FeedIdentification.cleanup_for_source(user: user, url: "https://example.com/feed.xml")
      FeedIdentification.cleanup_for_source(user: user, url: nil)
    end
  end
end
