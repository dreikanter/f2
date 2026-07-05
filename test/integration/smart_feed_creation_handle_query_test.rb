require "test_helper"

# Integration test for User Story 3 (handle / query inputs).
# Walks the detection-only paths since both flows are AI-backed and
# saving a feed isn't materially different from the website-extractor
# case already covered by smart_feed_creation_ai_website_test.rb.
class SmartFeedCreationHandleQueryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  test "#create should detect a handle input and offer the AI candidate" do
    sign_in_as(user)

    post feed_identifications_path, params: { input: "@alice" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_identifications_path, params: { input: "@alice" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "candidate.llm"
  end

  test "#create should detect a free-text query and offer the AI candidate" do
    sign_in_as(user)

    post feed_identifications_path, params: { input: "climate change" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_identifications_path, params: { input: "climate change" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "candidate.llm"
  end

  test "#create should render the personalized candidate summary for a handle input" do
    sign_in_as(user)

    post feed_identifications_path, params: { input: "@alice" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_identifications_path, params: { input: "@alice" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    # Multi-candidate would render the chooser; single-candidate renders the
    # source caption. Either way the user's input appears in the form copy.
    assert_includes response.body, "@alice"
  end
end
