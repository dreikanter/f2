require "test_helper"

class FeedIdentificationsFormTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
  end

  def user
    @user ||= regular_user
  end

  test "#create should open the webhook form without detection copy" do
    sign_in_as(user)

    assert_no_enqueued_jobs(only: FeedIdentificationJob) do
      post feed_identification_path,
           params: { webhook: "1" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_select "[data-key='form.webhook-note'][role='alert']", count: 1
    assert_select "input[data-key='form.name'] + p", text: "Choose a name for this feed."
    assert_not_includes response.body, "We couldn't automatically detect a name"
  end

  test "#new should render one shared action row for the selected mode" do
    sign_in_as(user)
    get new_feed_path

    assert_response :success
    assert_select "#feed-form input[type=submit]", count: 1
    assert_select "[data-key='entry.submit'][form='entry-link-form'][data-turbo-submits-with='Checking…']"
    assert_select "[data-key='entry.actions'] a", text: "Cancel", count: 1
    assert_select "[data-key='entry.actions'] a[href='#{feeds_path}']:not([data-turbo-method])"
  end

  test "#create should show the checking status and disable submission" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    post feed_identification_path,
         params: { url: url },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "[data-key='entry.checking-status']", text: "Checking this feed. This usually takes a few seconds."
    assert_select "#feed-form input[type=submit]", count: 1
    assert_select "[data-key='entry.submit'][form='entry-link-form'][value='Checking…'][disabled]"
    assert_select "[data-key='entry.actions'] a", text: "Cancel", count: 1
    assert_select "[data-key='entry.cancel-check'][href='#{feed_identification_path(url: url)}'][data-turbo-method='delete']"
  end
end
