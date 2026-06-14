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

  test "#build_recommended_feed should write input under the top candidate's input_shape" do
    identification = FeedIdentification.new(
      user: user,
      input: "https://example.com/feed.xml",
      status: :success,
      candidates: [
        { "profile_key" => "rss", "title" => "Example Feed", "rank" => 0 }
      ]
    )

    feed = identification.build_recommended_feed(user)

    assert_equal "rss", feed.feed_profile_key
    assert_equal "Example Feed", feed.name
    assert_equal "https://example.com/feed.xml", feed.params["url"]
    assert_equal user, feed.user
  end

  test "#build_recommended_feed should use the query input_shape for search profiles" do
    identification = FeedIdentification.new(
      user: user,
      input: "climate change",
      status: :success,
      candidates: [
        { "profile_key" => "llm_web_search", "title" => nil, "rank" => 0 }
      ]
    )

    feed = identification.build_recommended_feed(user)

    assert_equal "climate change", feed.params["query"]
    assert_nil feed.params["url"]
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
