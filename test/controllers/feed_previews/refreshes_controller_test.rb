require "test_helper"

class FeedPreviews::RefreshesControllerTest < ActionDispatch::IntegrationTest
  TURBO_STREAM = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  def user
    @user ||= create(:user)
  end

  def preview(status = :completed)
    @preview ||= create(:feed_preview, status, user: user, feed_profile_key: "rss",
                                               params: { "url" => "http://example.com/feed.xml" })
  end

  test "#create should restart the run and clear the last result" do
    sign_in_as(user)
    preview

    assert_no_difference("FeedPreview.count") do
      assert_enqueued_with(job: FeedPreviewJob) do
        post feed_preview_refresh_url(preview), headers: TURBO_STREAM
      end
    end

    assert_response :success
    assert_match(/data-key="preview.processing"/, response.body)
    preview.reload
    assert preview.pending?
    assert_nil preview.data
  end

  test "#create should rotate the run id so the previous job can't write back" do
    sign_in_as(user)
    was = preview(:processing).run_id

    post feed_preview_refresh_url(preview), headers: TURBO_STREAM

    refute_equal was, preview.reload.run_id
  end

  test "#create should not reach another user's preview" do
    sign_in_as(user)
    stranger = create(:feed_preview, :completed, user: create(:user), feed_profile_key: "rss",
                                                 params: { "url" => "http://example.com/feed.xml" })

    post feed_preview_refresh_url(stranger)

    assert_response :not_found
  end

  test "#create should require a signed-in user" do
    post feed_preview_refresh_url(preview)

    assert_redirected_to new_session_path
  end
end
