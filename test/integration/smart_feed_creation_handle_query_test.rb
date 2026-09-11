require "test_helper"

# The two entry modes for a non-link input: "Follow with AI" bridges
# straight to a draft AI feed, while a non-link typed into the link mode
# ("Follow a feed or channel") re-renders the entry form with the AI panel
# carrying the text; switching the mode radio is the bridge.
class SmartFeedCreationHandleQueryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  test "Follow with AI bridges a free-text prompt straight to a draft AI feed" do
    sign_in_as(user)

    assert_no_enqueued_jobs(only: FeedIdentificationJob) do
      post feed_identifications_path, params: { prompt: "climate change" },
                                      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, 'data-identification-state="complete"'
    assert_includes response.body, "climate change"
  end

  test "the link mode hints at the AI mode and carries the text over when the input isn't a link" do
    sign_in_as(user)

    post feed_identifications_path, params: { url: "@alice" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, 'data-identification-state="error"'
    assert_select "[data-key='entry.error']", text: /look like a link/
    assert_select "textarea#entry-ai-input", text: "@alice"
  end
end
