require "test_helper"

class FeedHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "#feed_target_group_link should link to the group on the token's instance" do
    access_token = create(:access_token, :active, host: "https://freefeed.net")
    feed = build(:feed, access_token: access_token, target_group: "testgroup")

    result = feed_target_group_link(feed)

    assert_includes result, %(href="https://freefeed.net/testgroup")
    assert_includes result, "freefeed.net/testgroup"
  end

  test "#feed_target_group_link should fall back to the bare group name without an access token" do
    feed = build(:feed, :without_access_token, target_group: "testgroup")

    assert_equal "testgroup", feed_target_group_link(feed)
  end

  test "#feed_target_group_link should return nil when the feed has no target group" do
    access_token = create(:access_token, :active)
    feed = build(:feed, access_token: access_token, target_group: nil)

    assert_nil feed_target_group_link(feed)
  end

  test "#feed_missing_enablement_parts should return both missing parts" do
    feed = build(:feed, :without_access_token)
    result = feed_missing_enablement_parts(feed)

    assert_equal ["active access token", "target group"], result
  end

  test "#feed_missing_enablement_parts should return missing access token only" do
    feed = build(:feed, :without_access_token, target_group: "test_group")
    result = feed_missing_enablement_parts(feed)

    assert_equal ["active access token"], result
  end

  test "#feed_missing_enablement_parts should return missing target group only" do
    access_token = create(:access_token, :active)
    feed = build(:feed, access_token: access_token, target_group: nil)
    result = feed_missing_enablement_parts(feed)

    assert_equal ["target group"], result
  end

  test "#feed_missing_enablement_parts should return missing access token when inactive" do
    access_token = create(:access_token, :inactive)
    feed = build(:feed, access_token: access_token, target_group: "test_group")
    result = feed_missing_enablement_parts(feed)

    assert_equal ["active access token"], result
  end

  test "#feed_missing_enablement_parts should return empty array when all requirements met" do
    access_token = create(:access_token, :active)
    feed = build(:feed, access_token: access_token, target_group: "test_group")
    result = feed_missing_enablement_parts(feed)

    assert_equal [], result
  end

  test "#feed_missing_enablement_parts should not expect source or schedule for a webhook feed" do
    feed = build(:feed, :webhook, name: "")
    result = feed_missing_enablement_parts(feed)

    assert_equal ["name"], result
  end

  test "#feed_missing_enablement_parts should include name when blank" do
    access_token = create(:access_token, :active)
    feed = build(:feed, access_token: access_token, target_group: "test_group", name: "")
    result = feed_missing_enablement_parts(feed)

    assert_includes result, "name"
  end

  test "#feed_missing_enablement_parts should include AI credential and model for an AI feed" do
    feed = build(:feed, feed_profile_key: "llm", params: { "prompt" => "ruby news" },
                        ai_credential: nil, ai_model: nil)
    result = feed_missing_enablement_parts(feed)

    assert_includes result, "active AI credential"
    assert_includes result, "AI model"
  end

  test "#feed_missing_enablement_parts should report an inactive AI credential" do
    credential = create(:ai_credential, :inactive)
    feed = build(:feed, user: credential.user, feed_profile_key: "llm",
                        params: { "prompt" => "ruby news" }, ai_credential: credential, ai_model: "claude-sonnet-4-6")
    result = feed_missing_enablement_parts(feed)

    assert_equal ["active AI credential"], result
  end

  test "#feed_missing_enablement_parts should allow a missing search credential" do
    credential = create(:ai_credential, :active)
    feed = build(:feed, user: credential.user, feed_profile_key: "llm",
                        params: { "prompt" => "ruby news" }, ai_credential: credential,
                        ai_model: "claude-sonnet-4-6", search_credential: nil)
    result = feed_missing_enablement_parts(feed)

    assert_empty result
  end

  test "#feed_missing_enablement_parts should allow an inactive search credential" do
    credential = create(:ai_credential, :active)
    search_credential = create(:search_credential, :inactive, user: credential.user)
    feed = build(:feed, user: credential.user, feed_profile_key: "llm",
                        params: { "prompt" => "ruby news" }, ai_credential: credential,
                        ai_model: "claude-sonnet-4-6", search_credential: search_credential)
    result = feed_missing_enablement_parts(feed)

    assert_empty result
  end

  test "#feed_missing_enablement_parts should be empty for a ready AI feed" do
    credential = create(:ai_credential, :active)
    feed = build(:feed, user: credential.user, feed_profile_key: "llm",
                        params: { "prompt" => "ruby news" }, ai_credential: credential, ai_model: "claude-sonnet-4-6")
    result = feed_missing_enablement_parts(feed)

    assert_equal [], result
  end

  test "#feed_enable_hint should list what the feed is missing" do
    feed = build(:feed, :without_access_token, target_group: "testgroup")

    assert_equal "To enable this feed, add an active access token.", feed_enable_hint(feed)
  end

  test "#feed_enable_hint should pick the article for a consonant part" do
    access_token = create(:access_token, :active)
    feed = build(:feed, access_token: access_token, target_group: nil)

    assert_equal "To enable this feed, add a target group.", feed_enable_hint(feed)
  end

  test "#feed_enable_hint should join several missing parts" do
    feed = build(:feed, :without_access_token, name: "")

    assert_equal "To enable this feed, add: name, active access token, and target group.", feed_enable_hint(feed)
  end

  test "#feed_enable_hint should allow enabling without search credentials" do
    credential = create(:ai_credential, :active)
    feed = build(:feed, user: credential.user, feed_profile_key: "llm",
                        params: { "prompt" => "ruby news" }, ai_credential: credential,
                        ai_model: "claude-sonnet-4-6", search_credential: nil)

    assert_equal "Complete setup to enable this feed", feed_enable_hint(feed)
  end

  test "#feed_enable_hint should fall back to a generic prompt when nothing is missing" do
    access_token = create(:access_token, :active)
    feed = build(:feed, access_token: access_token, target_group: "testgroup")

    assert_equal "Complete setup to enable this feed", feed_enable_hint(feed)
  end

  test "#feed_status_icon should render enabled icon" do
    feed = build(:feed, :enabled)

    result = feed_status_icon(feed)

    assert_includes result, "<svg"
    assert_includes result, "text-success"
    assert_includes result, 'title="Enabled"'
    assert_includes result, 'aria-label="Enabled"'
    assert_includes result, 'role="img"'
  end

  test "#feed_status_icon should render disabled icon" do
    feed = build(:feed, :disabled)

    result = feed_status_icon(feed)

    assert_includes result, "<svg"
    assert_includes result, "text-warning"
    assert_includes result, 'title="Disabled"'
    assert_includes result, 'aria-label="Disabled"'
    assert_includes result, 'role="img"'
  end

  test "#feed_status_icon should render draft icon" do
    feed = build(:feed, :draft)

    result = feed_status_icon(feed)

    assert_includes result, "<svg"
    assert_includes result, "text-muted"
    assert_includes result, 'title="Draft"'
    assert_includes result, 'aria-label="Draft"'
    assert_includes result, 'role="img"'
  end

  test "#feed_summary_line should describe active, inactive, and draft counts" do
    result = feed_summary_line(active_count: 2, inactive_count: 1, draft_count: 3)
    assert_equal "You have 2 active feeds, 1 inactive feed, and 3 draft feeds", result
  end

  test "#feed_summary_line should describe active and inactive counts" do
    result = feed_summary_line(active_count: 2, inactive_count: 1, draft_count: 0)
    assert_equal "You have 2 active feeds and 1 inactive feed", result
  end

  test "#feed_summary_line should handle single active count" do
    result = feed_summary_line(active_count: 1, inactive_count: 0, draft_count: 0)
    assert_equal "You have 1 active feed", result
  end

  test "#feed_summary_line should handle single inactive count" do
    result = feed_summary_line(active_count: 0, inactive_count: 3, draft_count: 0)
    assert_equal "You have 3 inactive feeds", result
  end

  test "#feed_summary_line should handle only draft count" do
    result = feed_summary_line(active_count: 0, inactive_count: 0, draft_count: 1)
    assert_equal "You have 1 draft feed", result
  end

  test "#feed_summary_line should describe active and draft counts" do
    result = feed_summary_line(active_count: 2, inactive_count: 0, draft_count: 1)
    assert_equal "You have 2 active feeds and 1 draft feed", result
  end

  test "#feed_summary_line should return nil for zero counts" do
    assert_nil feed_summary_line(active_count: 0, inactive_count: 0, draft_count: 0)
  end

  test "#feed_status_badge should render enabled badge for enabled feed" do
    feed = build(:feed, :enabled)
    result = feed_status_badge(feed)

    assert_equal "Enabled", result.instance_variable_get(:@text)
    assert_equal :success, result.instance_variable_get(:@color)
  end

  test "#feed_status_badge should render disabled badge for disabled feed" do
    feed = build(:feed, :disabled)
    result = feed_status_badge(feed)

    assert_equal "Disabled", result.instance_variable_get(:@text)
    assert_equal :warning, result.instance_variable_get(:@color)
  end

  test "#feed_status_badge should render draft badge for draft feed" do
    feed = build(:feed, :draft)
    result = feed_status_badge(feed)

    assert_equal "Draft", result.instance_variable_get(:@text)
    assert_equal :neutral, result.instance_variable_get(:@color)
  end

  test "#feed_actions_menu_items should list refresh, edit, purge, and delete for an enabled feed" do
    feed = create(:feed, :enabled, target_group: "testgroup")

    labels = menu_labels(feed)

    assert_equal ["Refresh", "Edit", "Purge feed…", "Delete feed…"], labels
  end

  test "#feed_actions_menu_items should omit refresh for a feed that is not enabled" do
    feed = create(:feed, :disabled, target_group: "testgroup")

    labels = menu_labels(feed)

    assert_equal ["Edit", "Purge feed…", "Delete feed…"], labels
  end

  test "#feed_actions_menu_items should omit purge when the feed has no target group" do
    feed = create(:feed, :enabled, target_group: "testgroup")
    feed.target_group = nil

    labels = menu_labels(feed)

    assert_equal ["Refresh", "Edit", "Delete feed…"], labels
  end

  test "#feed_actions_menu_items should separate purge and delete from the actions above them" do
    feed = create(:feed, :enabled, target_group: "testgroup")

    items = feed_actions_menu_items(feed)
    separators = items.each_index.select { |index| items[index][:separator] }

    assert_equal ["Purge feed…", "Delete feed…"], separators.map { |index| items[index + 1][:label] }
  end

  test "#feed_actions_menu_items should keep the delete separator when purge is unavailable" do
    feed = create(:feed, :enabled, target_group: "testgroup")
    feed.target_group = nil

    items = feed_actions_menu_items(feed)

    assert items[-2][:separator]
    assert_equal "Delete feed…", items[-1][:label]
  end

  test "#feed_actions_menu_items should wire refresh to a POST and danger actions to their modals" do
    feed = create(:feed, :enabled, target_group: "testgroup")

    items = feed_actions_menu_items(feed).reject { |item| item[:separator] }.index_by { |item| item[:label] }

    assert_equal :post, items["Refresh"][:method]
    assert_equal feed_refresh_path(feed), items["Refresh"][:href]
    assert_equal "purge-modal-#{feed.id}", items["Purge feed…"].dig(:data, :modal_trigger_modal_id_value)
    assert_equal "delete-feed-modal-#{feed.id}", items["Delete feed…"].dig(:data, :modal_trigger_modal_id_value)
  end

  test "#feed_missing_enablement_parts should not report source missing for an AI feed with a prompt" do
    access_token = create(:access_token, :active)
    feed = build(:feed, access_token: access_token, target_group: "testgroup",
                        feed_profile_key: "llm",
                        params: { "prompt" => "climate change news" })
    result = feed_missing_enablement_parts(feed)

    assert_not_includes result, "source"
  end

  test "#feed_missing_enablement_parts should report source missing when neither url nor query present" do
    access_token = create(:access_token, :active)
    feed = build(:feed, access_token: access_token, target_group: "testgroup",
                        params: {})
    result = feed_missing_enablement_parts(feed)

    assert_includes result, "source"
  end

  test "#webhook_curl_example should include the endpoint URL and the token" do
    snippet = webhook_curl_example("https://example.com/v1/posts", "secret-token")

    assert_includes snippet, "curl --request POST https://example.com/v1/posts"
    assert_includes snippet, "Authorization: Bearer secret-token"
  end

  test "#candidate_summary should fall back to the profile display name for URL profiles" do
    assert_equal "RSS Feed", candidate_summary("rss", "https://example.com/feed.xml")
    assert_equal "Reddit", candidate_summary("reddit", "https://reddit.com/r/ruby/")
  end

  test "#candidate_summary should personalize the AI profile with the user's input" do
    assert_equal "Follow with AI: \"climate change\"",
                 candidate_summary("llm", "climate change")
  end

  test "#candidate_summary should personalize the AI profile with a handle input" do
    assert_equal "Follow with AI: \"@alice\"",
                 candidate_summary("llm", "@alice")
  end

  private

  def menu_labels(feed)
    feed_actions_menu_items(feed).reject { |item| item[:separator] }.map { |item| item[:label] }
  end
end
