require "test_helper"
require "view_component/test_case"

class Admin::FeedDetailsComponentTest < ViewComponent::TestCase
  def feed
    @feed ||= create(:feed)
  end

  def render_component(target = feed)
    render_inline(Admin::FeedDetailsComponent.new(feed: target))
  end

  def value(result, key)
    result.at_css("[data-key='feed_details.#{key}.value']")
  end

  test "#call should show identity and destination with admin and external links" do
    result = render_component

    assert_equal feed.id, value(result, :id).at_css("code").text
    assert_equal "/admin/users/#{feed.user_id}", value(result, :owner).at_css("a")["href"]
    assert_equal feed.user.email_address, value(result, :owner).text
    assert_equal "Disabled", value(result, :status).text
    assert_equal "RSS Feed (rss)", value(result, :profile).text
    assert_equal feed.target_group_url, value(result, :target_group).at_css("a")["href"]
    assert_equal feed.url, value(result, :source).at_css("a")["href"]
    assert_equal "noopener", value(result, :source).at_css("a")["rel"]
    assert_includes value(result, :access_token).text, feed.access_token.name
    assert_includes value(result, :access_token).text, "Active"
    refute_includes result.to_html, feed.access_token.encrypted_token
  end

  test "#call should report cron configuration but not present a disabled schedule as pending" do
    create(:feed_schedule, feed: feed, next_run_at: 1.hour.ago)

    result = render_component

    assert_equal feed.cron_expression, value(result, :schedule).at_css("code").text
    assert_equal "Not scheduled (disabled)", value(result, :next_run).text
    assert_equal "Never", value(result, :last_scheduled_run).text
    assert_equal "Never", value(result, :last_success).text
    assert_equal "0 / 10", value(result, :failures).text
  end

  test "#call should show interval timing and distinguish future runs from due runs" do
    freeze_time do
      target = create(:feed, :enabled, refresh_interval: 2.hours.to_i, cron_expression: nil)
      create(:feed_schedule, feed: target, last_run_at: 1.hour.ago, next_run_at: 1.hour.from_now)

      result = render_component(target)

      assert_equal "Every 2 hours", value(result, :schedule).text
      assert_equal target.feed_schedule.last_run_at.iso8601, value(result, :last_scheduled_run).at_css("time")["datetime"]
      assert_equal target.feed_schedule.next_run_at.iso8601, value(result, :next_run).at_css("time")["datetime"]
      assert_includes value(result, :next_run).text, "in 1 hour"

      target.feed_schedule.update!(next_run_at: 10.minutes.ago)
      result = render_component(target)

      assert_includes value(result, :next_run).text, "(due)"
    end
  end

  test "#call should show import settings and explicit profile options" do
    feed.update!(import_after: 3.days.ago, images_only: true, consecutive_failures: 4,
                 params: feed.params.merge("content_in_comments" => true, "max_comments" => 5))

    result = render_component

    assert_equal feed.import_after.iso8601, value(result, :import_after).at_css("time")["datetime"]
    assert_equal "Yes", value(result, :images_only).text
    assert_equal "Yes", value(result, "option.content_in_comments").text
    assert_equal "5", value(result, "option.max_comments").text
    assert_equal "4 / 10", value(result, :failures).text
  end

  test "#call should show effective defaults without treating false as missing" do
    result = render_component

    assert_equal "No cutoff", value(result, :import_after).text
    assert_equal "No", value(result, :images_only).text
    assert_equal "No (default)", value(result, "option.content_in_comments").text
    assert_equal "No limit", value(result, "option.max_comments").text

    feed.update!(params: feed.params.merge("content_in_comments" => false))
    assert_equal "No", value(render_component, "option.content_in_comments").text
  end

  test "#call should show incomplete draft setup and preserve an unlinked target group" do
    target = build_stubbed(:feed, :draft, :without_access_token, cron_expression: nil, feed_profile_key: "rss")
    target.params = {}
    target.target_group = "unfinished"

    result = render_component(target)

    assert_equal "Not configured", value(result, :source).text
    assert_equal "Not configured", value(result, :access_token).text
    assert_equal "Not configured", value(result, :schedule).text
    assert_equal "unfinished", value(result, :target_group).text
    assert_nil value(result, :target_group).at_css("a")
    assert_includes value(result, :setup).text, "source"
    assert_includes value(result, :setup).text, "active access token"
    assert_includes value(result, :setup).text, "schedule"
  end

  test "#call should show webhook ingestion without polling or secret endpoint details" do
    target = create(:feed, :webhook, last_successful_refresh_at: 1.hour.ago)
    result = render_component(target)

    assert_equal "Webhook-driven", value(result, :source).text
    assert_equal "Webhook-driven", value(result, :schedule).text
    assert_equal "Last post received", result.at_css("[data-key='feed_details.last_success.label']").text
    assert_nil value(result, :next_run)
    assert_nil value(result, :failures)
    assert_nil value(result, :import_after)
    assert_nil value(result, :images_only)
    assert_nil value(result, :ai_credential)
  end

  test "#call should show AI configuration and credential states without secrets" do
    ai = create(:ai_credential, :active, user: feed.user)
    search = create(:search_credential, :inactive, user: feed.user)
    target = create(:feed, user: feed.user, feed_profile_key: "llm", params: { "prompt" => "Find science news" },
                           ai_credential: ai, ai_model: "example-model", search_credential: search)

    result = render_component(target)

    assert_includes value(result, :ai_credential).text, ai.provider_name
    assert_includes value(result, :ai_credential).text, ai.display_name
    assert_includes value(result, :ai_credential).text, "Active"
    assert_equal "example-model", value(result, :ai_model).at_css("code").text
    assert_includes value(result, :search_credential).text, search.display_name
    assert_includes value(result, :search_credential).text, "Inactive"
    refute_includes result.to_html, ai.credential_data["api_key"]
    refute_includes result.to_html, search.credential_data["api_key"]
  end

  test "#call should wrap and escape free text without turning unsafe schemes into links" do
    prompt = "javascript:alert(1)\n<script>alert('test')</script> " + "long text " * 100
    target = create(:feed, feed_profile_key: "llm", params: { "prompt" => prompt }, description: "<img src=x onerror=alert(1)>")

    result = render_component(target)

    assert_equal prompt, value(result, :source).text
    assert_nil value(result, :source).at_css("a, script")
    assert_nil value(result, :description).at_css("img")
    assert_nil value(result, :source).at_css(".truncate")
    assert_equal "Not configured", value(result, :ai_credential).text
    assert_equal "Not configured", value(result, :ai_model).text
    assert_equal "Not configured", value(result, :search_credential).text
  end

  test "#call should tolerate a missing profile on historical drafts" do
    target = build_stubbed(:feed, :draft)
    target.feed_profile_key = nil

    result = render_component(target)

    assert_equal "Not configured", value(result, :profile).text
    assert_equal "Not configured", value(result, :schedule).text
    assert_includes value(result, :setup).text, "feed profile"
  end
end
