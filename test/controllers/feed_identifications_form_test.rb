require "test_helper"

class FeedIdentificationsFormTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
  end

  def user
    @user ||= create(:user)
  end

  test "#create should open the webhook form without detection copy" do
    sign_in_as(user)

    assert_no_enqueued_jobs(only: FeedIdentificationJob) do
      post feed_identifications_path,
           params: { webhook: "1" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_select "[data-key='form.webhook-note'][role='alert']", count: 1
    assert_select "input[data-key='form.name'] + p", text: "Choose a name for this webhook feed."
    assert_not_includes response.body, "We couldn't automatically detect a name"
  end

  test "#new should use state labels that match each feed type" do
    sign_in_as(user)
    get new_feed_path

    assert_response :success
    assert_select "[data-key='entry.actions-link'] input[data-turbo-submits-with='Checking…']", count: 1
    assert_select "[data-key='entry.actions-ai'] input[data-turbo-submits-with='Preparing…']", count: 1
    assert_select "[data-key='entry.actions-webhook'] input[data-turbo-submits-with='Preparing…']", count: 1
  end

  test "#create should disable and visibly dim the checking submit button" do
    sign_in_as(user)

    post feed_identifications_path,
         params: { url: "http://example.com/feed.xml" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    button = css_select("input[type=submit][value='Checking…'][disabled]").first
    assert button
    assert_includes button["class"], "disabled:opacity-60"
    assert_includes button["class"], "disabled:cursor-not-allowed"
    assert_includes button["class"], "disabled:hover:bg-brand"
  end
end
