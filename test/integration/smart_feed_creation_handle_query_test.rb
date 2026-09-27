require "test_helper"

class SmartFeedCreationHandleQueryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= regular_user
  end

  test "Follow with AI bridges a free-text prompt straight to a draft AI feed" do
    sign_in_as(user)

    assert_no_enqueued_jobs(only: FeedIdentificationJob) do
      post feed_identification_path, params: { prompt: "climate change" },
                                      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, 'data-identification-state="complete"'
    assert_includes response.body, "climate change"
  end

  test "the link mode asks for a URL and keeps invalid input in the link field" do
    sign_in_as(user)

    post feed_identification_path, params: { url: "@alice" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, 'data-identification-state="error"'
    assert_select "[data-key='entry.mode-link'] input[type=radio][checked]"
    assert_select "[data-key='form.entry-link'][value='@alice']"
    assert_select "[data-key='entry.error']", text: "That doesn't look like a link. Paste a feed or page URL."
    assert_select "[data-key='form.entry-ai']", text: ""
  end
end
