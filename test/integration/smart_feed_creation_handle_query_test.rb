require "test_helper"

# A handle or free-text query isn't a link, so Mode A bridges it straight to a
# draft AI feed (spec 005 §1) — no detection, no identification job, the prompt
# is the source.
class SmartFeedCreationHandleQueryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  test "#create should bridge a handle straight to a draft AI feed" do
    sign_in_as(user)

    assert_no_enqueued_jobs(only: FeedIdentificationJob) do
      post feed_identifications_path, params: { input: "@alice" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, 'data-identification-state="complete"'
    assert_includes response.body, "@alice"
  end

  test "#create should bridge a free-text query straight to a draft AI feed" do
    sign_in_as(user)

    assert_no_enqueued_jobs(only: FeedIdentificationJob) do
      post feed_identifications_path, params: { input: "climate change" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, 'data-identification-state="complete"'
    assert_includes response.body, "climate change"
  end
end
