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
