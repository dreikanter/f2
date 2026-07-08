require "test_helper"

# The two entry modes for a non-link input (spec 005 §1): Mode B ("Follow with
# AI") bridges straight to a draft AI feed, while a non-link typed in Mode A
# ("Follow a feed or channel") is offered the bridge rather than guessed.
class SmartFeedCreationHandleQueryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  test "Mode B bridges a free-text prompt straight to a draft AI feed" do
    sign_in_as(user)

    assert_no_enqueued_jobs(only: FeedIdentificationJob) do
      post feed_identifications_path, params: { prompt: "climate change" },
                                      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, 'data-identification-state="complete"'
    assert_includes response.body, "climate change"
  end

  test "Mode A offers the AI bridge when the input isn't a link" do
    sign_in_as(user)

    post feed_identifications_path, params: { url: "@alice" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, 'data-identification-state="error"'
    assert_includes response.body, "identification.ai-bridge"
  end
end
