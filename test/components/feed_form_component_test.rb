require "test_helper"
require "view_component/test_case"

# The component's logic is tested directly (no render needed); the rendered
# markup is covered by the feeds and feed identifications controller tests.
class FeedFormComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed(*traits, **attrs)
    build(:feed, *traits, user: user, **attrs)
  end

  def ai_feed(**attrs)
    feed(feed_profile_key: "llm", params: { "prompt" => "follow the news" }, **attrs)
  end

  def component(feed, **options)
    FeedFormComponent.new(feed: feed, **options)
  end

  def candidate(profile_key)
    FeedIdentification::Candidate.new({ "profile_key" => profile_key, "test_status" => "passed", "posts_found" => 1 })
  end

  test "#edit_mode? should follow feed persistence" do
    assert_not component(feed).edit_mode?
    assert component(create(:feed, user: user)).edit_mode?
  end

  test "#show_chooser? should require at least two candidates" do
    assert_not component(feed).show_chooser?
    assert_not component(feed, candidates: [candidate("rss")]).show_chooser?
    assert component(feed, candidates: [candidate("rss"), candidate("llm")]).show_chooser?
  end

  test "#preview_source_keys should map every candidate while the chooser is live" do
    subject = component(feed, candidates: [candidate("rss"), candidate("llm")])
    assert_equal({ "rss" => "url", "llm" => "prompt" }, subject.preview_source_keys)
  end

  test "#preview_source_keys should fall back to the feed's own profile without a chooser" do
    assert_equal({ "rss" => "url" }, component(feed, candidates: [candidate("rss")]).preview_source_keys)
  end

  test "#ai_prompt_editable? should be true only for AI-backed profiles" do
    assert component(ai_feed).ai_prompt_editable?
    assert_not component(feed).ai_prompt_editable?
  end

  test "#source_editable? should allow URL edits only when editing a deterministic feed" do
    assert component(create(:feed, user: user)).source_editable?
    assert_not component(feed).source_editable?
    assert_not component(create(:feed, user: user, feed_profile_key: "llm", params: { "prompt" => "x" })).source_editable?
  end

  test "#prompt_backfill_warning? should appear only for a live feed" do
    assert component(create(:feed, user: user)).prompt_backfill_warning?
    assert_not component(create(:feed, :draft, user: user)).prompt_backfill_warning?
    assert_not component(feed).prompt_backfill_warning?
  end

  test "#source_url_value should prefer the attempted URL over the saved source" do
    assert_equal "https://example.com/feed.xml", component(feed).source_url_value
    assert_equal "https://new.example.com", component(feed, attempted_url: "https://new.example.com").source_url_value
  end

  test "#name_hint should invite editing a detected name" do
    assert_equal "You can edit this name if you'd like.", component(feed).name_hint
  end

  test "#name_hint should ask for a name for a sourceless feed" do
    assert_equal "Choose a name for this feed.", component(feed(:webhook, name: nil)).name_hint
  end

  test "#name_hint should explain when detection found no name" do
    assert_equal "We couldn't automatically detect a name. Please enter one.", component(feed(name: nil)).name_hint
  end

  test "#token_swap? should be true only when the feed's token went inactive" do
    assert component(feed(access_token: build(:access_token, :inactive, user: user))).token_swap?
    assert_not component(feed).token_swap?
    assert_not component(feed(:without_access_token)).token_swap?
  end

  test "#selected_token_id should keep the feed's own active token" do
    token = create(:access_token, :active, user: user)
    create(:access_token, :active, user: user, host: "https://a.example.com")
    assert_equal token.id, component(feed(access_token: token)).selected_token_id
  end

  test "#selected_token_id should preselect a working token on a swap" do
    replacement = create(:access_token, :active, user: user)
    inactive = create(:access_token, :inactive, user: user)
    assert_equal replacement.id, component(feed(access_token: inactive)).selected_token_id
  end

  test "#import_after_on? should switch on for a pending profile change" do
    assert component(feed, profile_changed: true).import_after_on?
    assert_not component(feed).import_after_on?
    assert component(feed(import_after: 1.day.ago)).import_after_on?
  end

  test "#import_after_date_value should seed today when a profile change turned it on" do
    assert_equal Date.current.iso8601, component(feed, profile_changed: true).import_after_date_value
    assert_nil component(feed).import_after_date_value
    assert_equal "2026-01-15", component(feed(import_after: Time.utc(2026, 1, 15, 10, 30))).import_after_date_value
  end

  test "#import_after_time_value should default to midnight" do
    assert_equal "00:00", component(feed).import_after_time_value
    assert_equal "10:30", component(feed(import_after: Time.utc(2026, 1, 15, 10, 30))).import_after_time_value
  end

  test "#selected_schedule_interval should fall back to the default interval" do
    assert_equal "6h", component(feed).selected_schedule_interval
    assert_equal Feed::DEFAULT_SCHEDULE_INTERVAL, component(feed(cron_expression: nil)).selected_schedule_interval
  end

  test "#enable_missing should list every missing setup piece" do
    assert_equal ["a FreeFeed access token"], component(feed).enable_missing(nil)
    assert_equal ["a FreeFeed access token", "AI credentials", "search credentials"],
                 component(ai_feed).enable_missing(nil)
  end

  test "#enable_missing should be empty when the setup is complete" do
    create(:access_token, :active, user: user)
    assert_empty component(feed).enable_missing(nil)
  end

  test "#enable_blocked? should lock the checkbox while setup pieces are missing" do
    assert component(feed).enable_blocked?(nil)
  end

  test "#enable_blocked? should keep an enabled feed's checkbox interactive" do
    assert_not component(feed(:enabled)).enable_blocked?(nil)
  end

  test "#submit_label should reflect the checking state" do
    assert_equal "Save feed", component(feed).submit_label
    assert_equal "Checking…", component(feed, checking: true).submit_label
  end
end
