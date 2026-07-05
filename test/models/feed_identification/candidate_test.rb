require "test_helper"

class FeedIdentification::CandidateTest < ActiveSupport::TestCase
  def candidate(attributes)
    FeedIdentification::Candidate.new(attributes)
  end

  test "#profile_key and #title should read the attributes" do
    subject = candidate("profile_key" => "rss", "title" => "Example")

    assert_equal "rss", subject.profile_key
    assert_equal "Example", subject.title
  end

  test "#posts_found should default to zero" do
    assert_equal 0, candidate({}).posts_found
    assert_equal 3, candidate("posts_found" => 3).posts_found
  end

  test "status predicates should reflect test_status" do
    assert candidate("test_status" => "passed").passed?
    assert candidate("test_status" => "failed").failed?
    assert candidate("test_status" => "unreachable").unreachable?
  end

  test "status predicates should be false for a different verdict" do
    subject = candidate("test_status" => "passed")

    assert_not subject.failed?
    assert_not subject.unreachable?
  end

  test "status predicates should be false when no verdict is present" do
    subject = candidate({})

    assert_not subject.passed?
    assert_not subject.failed?
    assert_not subject.unreachable?
  end
end
