require "test_helper"

class Development::SampleFeedsControllerTest < ActionDispatch::IntegrationTest
  def dev_user
    @dev_user ||= create(:user, :dev)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "#show should require authentication" do
    get development_sample_feed_path

    assert_response :redirect
  end

  test "#show should require dev permission" do
    sign_in_as(regular_user)
    get development_sample_feed_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "#show should serve a parseable RSS feed with posts by default" do
    sign_in_as(dev_user)
    get development_sample_feed_path

    assert_response :success
    assert_equal "application/rss+xml", @response.media_type
    assert_equal 5, Feedjira.parse(@response.body).entries.size
  end

  test "#show should fall back to the sample feed for an unknown state" do
    sign_in_as(dev_user)
    get development_sample_feed_path(state: "nonsense")

    assert_response :success
    assert_equal 5, Feedjira.parse(@response.body).entries.size
  end

  test "#show should serve a valid but empty feed" do
    sign_in_as(dev_user)
    get development_sample_feed_path(state: "empty")

    assert_response :success
    parsed = Feedjira.parse(@response.body)
    assert_empty parsed.entries
    assert parsed.title.present?, "empty feed should still carry a title so it reads as valid"
  end

  test "#show should serve a parseable Atom feed" do
    sign_in_as(dev_user)
    get development_sample_feed_path(state: "atom")

    assert_response :success
    assert_equal "application/atom+xml", @response.media_type
    assert_equal 3, Feedjira.parse(@response.body).entries.size
  end

  test "#show should serve an RSS-looking payload that does not parse for the malformed state" do
    sign_in_as(dev_user)
    get development_sample_feed_path(state: "malformed")

    assert_response :success
    assert_match(/<rss[\s>]/, @response.body)

    parsed = begin
      Feedjira.parse(@response.body)
    rescue StandardError
      nil
    end
    assert(
      parsed.nil? || (parsed.entries.empty? && parsed.title.blank?),
      "malformed payload should not parse into a recognizable feed"
    )
  end

  test "#show should serve a plain HTML page with no feed markup for the not_feed state" do
    sign_in_as(dev_user)
    get development_sample_feed_path(state: "not_feed")

    assert_response :success
    assert_equal "text/html", @response.media_type
    assert_no_match(/<rss[\s>]|<feed[\s>]|<rdf:RDF/i, @response.body)
  end

  test "#show should simulate HTTP error statuses" do
    sign_in_as(dev_user)

    {
      "not_found" => 404,
      "forbidden" => 403,
      "unauthorized" => 401,
      "server_error" => 500
    }.each do |state, code|
      get development_sample_feed_path(state: state)
      assert_response code, "state #{state} should respond with #{code}"
    end
  end

  test "#show should redirect to the valid feed for the redirect state" do
    sign_in_as(dev_user)
    get development_sample_feed_path(state: "redirect")

    assert_redirected_to development_sample_feed_path(state: "ok")
  end

  test "#show should redirect to itself for the redirect_loop state" do
    sign_in_as(dev_user)
    get development_sample_feed_path(state: "redirect_loop")

    assert_redirected_to development_sample_feed_path(state: "redirect_loop")
  end

  test "#show should serve the feed after the configured delay for the slow state" do
    sign_in_as(dev_user)
    get development_sample_feed_path(state: "slow", delay: 0)

    assert_response :success
    assert_equal 5, Feedjira.parse(@response.body).entries.size
  end

  test "every catalogued state should respond without error" do
    sign_in_as(dev_user)

    Development::SampleFeedsController::STATES.each_key do |state|
      get development_sample_feed_path(state: state, delay: 0)
      assert_includes 200..399, @response.status unless %w[not_found forbidden unauthorized server_error].include?(state)
    end
  end
end
