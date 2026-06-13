require "test_helper"

class FeedsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def feed
    @feed ||= create(:feed, user: user)
  end

  def other_feed
    @other_feed ||= create(:feed, user: create(:user))
  end

  test "#index should redirect to login when not authenticated" do
    get feeds_url
    assert_redirected_to new_session_path
  end

  test "#index should render feed list for authenticated user" do
    sign_in_as(user)
    feed
    get feeds_url
    assert_response :success
    assert_select "button[data-dropdown-toggle='feed-sort-menu']", 1
    assert_select "#feed-sort-menu a", 5
    assert_select "a[href='#{feed_path(feed)}']", minimum: 1
    assert_select "p", text: "You have 1 inactive feed"
  end

  test "#index should include drafts in summary line" do
    sign_in_as(user)
    create(:feed, :enabled, user: user)
    create(:feed, :disabled, user: user)
    create(:feed, :draft, user: user)
    create(:feed, :draft, user: user)

    get feeds_url

    assert_response :success
    assert_select "p", text: "You have 1 active feed, 1 inactive feed, and 2 draft feeds"
  end

  test "#index should render tailwind pagination controls" do
    sign_in_as(user)
    create_list(:feed, 4, user: user)

    get feeds_url, params: { per_page: 3 }

    assert_response :success
    assert_select "nav[aria-label='Feeds pagination']"
    assert_select "nav[aria-label='Feeds pagination'] ul[class*='inline-flex']", minimum: 1
    assert_select "div.text-center", text: /Showing/
  end

  test "#new should render when authenticated" do
    sign_in_as(user)
    get new_feed_url
    assert_response :success
  end

  test "#create should save and enable when checkbox checked and all fields valid" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "Test Feed",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h"
    }

    assert_difference("Feed.count", 1) do
      post feeds_path, params: { feed: feed_params, enable_feed: "1" }
    end

    feed = Feed.last
    assert_predicate feed, :enabled?
    assert_not_nil feed.feed_schedule
    assert_not_nil feed.feed_schedule.next_run_at
    assert_not_nil feed.feed_schedule.last_run_at
    assert_redirected_to feed_path(feed)
    assert_match "Feed created and enabled.", flash[:success]
  end

  test "#create should save as draft with blank name" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h"
    }

    assert_difference("Feed.count", 1) do
      post feeds_path, params: { feed: feed_params, enable_feed: "0" }
    end

    feed = Feed.last
    assert_predicate feed, :draft?
    assert_predicate feed.name, :blank?
    assert_redirected_to feed_path(feed)
  end

  test "#create should save as draft when checkbox unchecked" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "Test Feed",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h"
    }

    assert_difference("Feed.count", 1) do
      post feeds_path, params: { feed: feed_params, enable_feed: "0" }
    end

    feed = Feed.last
    assert_predicate feed, :draft?
    assert_redirected_to feed_path(feed)
    assert_match "Feed saved as draft", flash[:success]
  end

  test "#create should enable a feed without any preview" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "Test Feed",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h"
    }

    assert_difference("Feed.count", 1) do
      post feeds_path, params: { feed: feed_params, enable_feed: "1" }
    end

    feed = Feed.last
    assert_predicate feed, :enabled?
    assert_redirected_to feed_path(feed)
  end

  test "#create should persist as draft and re-render when enable-validation fails on a missing field" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "Test Feed",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      # target_group missing (required only when enabled)
      schedule_interval: "1h"
    }

    assert_difference("Feed.count", 1) do
      post feeds_path, params: { feed: feed_params, enable_feed: "1" }
    end

    assert_response :unprocessable_entity
    assert_predicate Feed.last, :draft?
    assert_match "Couldn't enable", flash[:alert]
    # Target group error rendered inline by _target_group_selector partial
    assert_select "#target-group-selector p.text-red-600", text: /can(?:'|&#39;)t be blank/
  end

  test "#create should fail without persisting when even draft validation fails" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "Test Feed",
      # feed_profile_key missing (required in every state, draft envelope)
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h"
    }

    assert_no_difference("Feed.count") do
      post feeds_path, params: { feed: feed_params, enable_feed: "0" }
    end

    assert_response :unprocessable_entity
  end

  test "#create should enable a feed even when the only preview is for a different source" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "Test Feed",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h"
    }

    create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
           params: { "url" => "http://other.example/feed.xml" }, ready_at: Time.current)

    assert_difference("Feed.count", 1) do
      post feeds_path, params: { feed: feed_params, enable_feed: "1" }
    end

    feed = Feed.last
    assert_predicate feed, :enabled?
    assert_redirected_to feed_path(feed)
  end

  test "#create should ignore state param and use enable_feed instead" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "Test Feed",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h",
      state: "enabled"  # Attempt to bypass UI
    }

    assert_difference("Feed.count", 1) do
      post feeds_path, params: { feed: feed_params, enable_feed: "0" }
    end

    feed = Feed.last
    assert_predicate feed, :draft?, "State should be draft despite state param"
  end

  test "#create should save as draft and redirect to token setup when commit signals token gate" do
    sign_in_as(user)

    assert_difference("Feed.count", 1) do
      post feeds_path, params: {
        feed: {
          url: "http://example.com/feed.xml",
          name: "Test Feed",
          feed_profile_key: "rss",
          target_group: "testgroup",
          schedule_interval: "1h"
        },
        commit: "save_as_draft_and_add_token"
      }
    end

    feed = Feed.last
    assert_predicate feed, :draft?
    assert_redirected_to new_access_token_path(feed_id: feed.id)
  end

  test "#create token-gate commit should ignore enable_feed=1" do
    sign_in_as(user)

    assert_difference("Feed.count", 1) do
      post feeds_path, params: {
        feed: {
          url: "http://example.com/feed.xml",
          name: "Test Feed",
          feed_profile_key: "rss",
          target_group: "testgroup",
          schedule_interval: "1h"
        },
        enable_feed: "1",
        commit: "save_as_draft_and_add_token"
      }
    end

    feed = Feed.last
    assert_predicate feed, :draft?, "Token gate commit must force draft regardless of enable_feed"
    assert_redirected_to new_access_token_path(feed_id: feed.id)
  end

  test "#create should save as draft and redirect to credential setup when commit signals gate" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "Test Feed",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h"
    }

    assert_difference("Feed.count", 1) do
      post feeds_path, params: {
        feed: feed_params,
        commit: "save_as_draft_and_add_credentials"
      }
    end

    feed = Feed.last
    assert_predicate feed, :draft?
    assert_redirected_to new_llm_credential_path(feed_id: feed.id)
  end

  test "#create gate-commit should ignore enable_feed=1" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "Test Feed",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h"
    }

    assert_difference("Feed.count", 1) do
      post feeds_path, params: {
        feed: feed_params,
        enable_feed: "1",
        commit: "save_as_draft_and_add_credentials"
      }
    end

    feed = Feed.last
    assert_predicate feed, :draft?, "Gate commit must force draft regardless of enable_feed"
    assert_redirected_to new_llm_credential_path(feed_id: feed.id)
  end

  test "#create should render form with errors on validation failure" do
    sign_in_as(user)

    feed_params = {
      url: "invalid-url",
      name: "",
      feed_profile_key: "rss"
    }

    assert_no_difference("Feed.count") do
      post feeds_path, params: { feed: feed_params }
    end

    assert_response :unprocessable_entity
    assert_select "h1", text: "New Feed"
  end

  test "#create should render expanded form with preserved data on validation failure" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "Test Feed",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "INVALID GROUP!",  # Invalid format (always validated)
      schedule_interval: "1h"
    }

    assert_no_difference("Feed.count") do
      post feeds_path, params: { feed: feed_params, enable_feed: "0" }
    end

    assert_response :unprocessable_entity
    assert_select "h1", text: "New Feed"

    # Verify expanded form is shown, not collapsed form
    assert_select "input[name='feed[url_display]'][disabled]"

    # Verify validation errors are shown
    assert_select "p.text-red-600", text: /lowercase letters/
  end

  test "#create should keep the expanded form for a query-shaped feed on validation failure" do
    sign_in_as(user)
    access_token

    feed_params = {
      name: "Search Feed",
      feed_profile_key: "llm_web_search",
      params: { query: "ruby news" },
      access_token_id: access_token.id,
      target_group: "INVALID GROUP!",  # Invalid format (always validated)
      schedule_interval: "1h"
    }

    post feeds_path, params: { feed: feed_params, enable_feed: "0" }

    assert_response :unprocessable_entity
    # Query-shaped feeds have a blank url; the expanded form must still render
    # (keyed off source_input, not url) so the preview button survives the error.
    assert_select "[data-key='preview.open']", count: 1
    assert_select "p.text-red-600", text: /lowercase letters/
  end

  test "#show should render feed owned by user" do
    sign_in_as(user)
    get feed_url(feed)
    assert_response :success
    assert_includes response.body, feed.name
    assert_select "a[href='#{edit_feed_path(feed)}']", text: "Edit"
  end

  test "#show should link to the Freefeed group regardless of feed state" do
    sign_in_as(user)
    disabled = create(:feed, :disabled, user: user, access_token: access_token, target_group: "testgroup")

    get feed_url(disabled)

    assert_response :success
    assert_select "a[href='#{access_token.host}/testgroup']",
                  text: "#{access_token.host_domain}/testgroup"
  end

  test "#show should not link to the Freefeed group when target group is missing" do
    sign_in_as(user)
    no_group = create(:feed, :without_access_token, user: user)

    get feed_url(no_group)

    assert_response :success
    assert_select "a[href$='/testgroup']", count: 0
  end

  test "#show should not offer a status toggle for a draft feed" do
    sign_in_as(user)
    draft = create(:feed, :draft, user: user)

    get feed_url(draft)

    assert_response :success
    assert_select "form[action='#{feed_status_path(draft)}']", count: 0
  end

  test "#show should not render a preview button" do
    sign_in_as(user)
    get feed_url(feed)
    assert_response :success
    assert_select "form[action='#{feed_preview_path}']", count: 0
  end

  test "#show should hide stats section when feed has no posts" do
    sign_in_as(user)
    get feed_url(feed)
    assert_response :success
    assert_select "h2", text: "Stats", count: 0
  end

  test "#show should show stats section when feed has posts" do
    create(:post, feed: feed)
    sign_in_as(user)
    get feed_url(feed)
    assert_response :success
    assert_select "h2", text: "Stats", count: 1
  end

  test "#show should render a recent activity section with the feed's events" do
    create(:event, type: "feed_auto_disabled", subject: feed, user: user, level: :warning,
                   message: "", metadata: { error_count: Feed::MAX_CONSECUTIVE_FAILURES })
    sign_in_as(user)

    get feed_url(feed)

    assert_response :success
    assert_select "h2", text: "Recent activity", count: 1
    assert_select "[data-key='events.entry'][data-event-type='feed_auto_disabled']"
    assert_select "[data-key='events.error_count']", text: "(10 failures in a row)"
  end

  test "#show should return not found for other user's feed" do
    sign_in_as(user)
    get feed_url(other_feed)
    assert_response :not_found
  end

  test "#edit should render for own feed" do
    sign_in_as(user)
    get edit_feed_url(feed)
    assert_response :success
    assert_select "label", text: "Source"
    assert_select "p.text-slate-500", text: "Source and type can't be changed after creation. Start a new feed to follow a different source."
  end

  test "#edit should render Save feed button and unchecked always-interactable Enable checkbox for a draft" do
    sign_in_as(user)
    draft = create(:feed, :draft, user: user)

    get edit_feed_url(draft)

    assert_response :success
    assert_select "input[type=submit][value='Save feed']"
    assert_select "input[type=checkbox][name='enable_feed']:not([disabled])"
    assert_select "input[type=checkbox][name='enable_feed'][checked]", false,
                  "Enable checkbox should not be checked for a draft feed"
  end

  test "#edit should render Save feed button with unchecked Enable checkbox for a disabled feed" do
    sign_in_as(user)
    disabled = create(:feed, :disabled, user: user)

    get edit_feed_url(disabled)

    assert_response :success
    assert_select "input[type=submit][value='Save feed']"
    assert_select "input[type=checkbox][name='enable_feed']:not([disabled])"
    assert_select "input[type=checkbox][name='enable_feed'][checked]", false,
                  "Enable checkbox should not be checked for a disabled feed"
  end

  test "#edit should render Save feed button with checked Enable checkbox for an enabled feed" do
    sign_in_as(user)
    enabled = create(:feed, :enabled, user: user, access_token: access_token)

    get edit_feed_url(enabled)

    assert_response :success
    assert_select "input[type=submit][value='Save feed']"
    assert_select "input[type=checkbox][name='enable_feed'][checked]:not([disabled])"
  end

  test "#update should update feed with valid params" do
    sign_in_as(user)
    new_token = create(:access_token, user: user, host: "https://freefeed.net")

    patch feed_url(feed), params: {
      feed: {
        name: "Updated Feed Name",
        access_token_id: new_token.id,
        target_group: "new-group",
        schedule_interval: "2h"
      }
    }

    assert_redirected_to feed_path(feed)
    follow_redirect!
    assert_match "Feed 'Updated Feed Name' was successfully updated", response.body

    feed.reload
    assert_equal "Updated Feed Name", feed.name
    assert_equal new_token.id, feed.access_token_id
    assert_equal "new-group", feed.target_group
    assert_equal "2h", feed.schedule_interval
  end

  test "#edit should render collapsed advanced options when no import threshold is set" do
    sign_in_as(user)

    get edit_feed_url(feed)

    assert_response :success
    assert_select 'details[data-key="form.advanced-options"]:not([open])'
    assert_select '[data-key="form.import-after-fields"].hidden'
    assert_select 'input[name="feed[import_after_enabled]"][type=checkbox][checked]', false
  end

  test "#edit should expand advanced options when an import threshold is set" do
    sign_in_as(user)
    feed.update!(import_after: Time.utc(2026, 1, 15, 10, 30))

    get edit_feed_url(feed)

    assert_response :success
    assert_select 'details[data-key="form.advanced-options"][open]'
    assert_select 'input[name="feed[import_after_enabled]"][type=checkbox][checked]'
    assert_select 'input[data-key="form.import-after-date"][value="2026-01-15"]'
    assert_select 'input[data-key="form.import-after-time"][value="10:30"]'
  end

  test "#update should set import_after from threshold params" do
    sign_in_as(user)

    patch feed_url(feed), params: {
      feed: {
        import_after_enabled: "1",
        import_after_date: "2026-01-15",
        import_after_time: "10:30"
      }
    }

    assert_redirected_to feed_path(feed)
    assert_equal Time.zone.parse("2026-01-15 10:30"), feed.reload.import_after
  end

  test "#update should clear import_after when threshold checkbox is unchecked" do
    sign_in_as(user)
    feed.update!(import_after: Time.utc(2026, 1, 15, 10, 30))

    patch feed_url(feed), params: {
      feed: {
        import_after_enabled: "0",
        import_after_date: "2026-01-15",
        import_after_time: "10:30"
      }
    }

    assert_redirected_to feed_path(feed)
    assert_nil feed.reload.import_after
  end

  test "#update should rerender with an error for an invalid threshold date" do
    sign_in_as(user)

    patch feed_url(feed), params: {
      feed: {
        import_after_enabled: "1",
        import_after_date: "not-a-date",
        import_after_time: ""
      }
    }

    assert_response :unprocessable_entity
    assert_select 'details[data-key="form.advanced-options"][open]'
    assert_match "Isn&#39;t a valid date and time", response.body
    assert_nil feed.reload.import_after
  end

  test "#create should accept import threshold params" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "Test Feed",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h",
      import_after_enabled: "1",
      import_after_date: "2026-01-15",
      import_after_time: "10:30"
    }

    assert_difference("Feed.count", 1) do
      post feeds_path, params: { feed: feed_params, enable_feed: "0" }
    end

    assert_equal Time.zone.parse("2026-01-15 10:30"), Feed.last.import_after
  end

  test "#update should show additional message for enabled feeds" do
    sign_in_as(user)
    enabled_feed = create(:feed, user: user, state: :enabled, access_token: access_token)

    patch feed_url(enabled_feed), params: {
      feed: {
        name: "Updated Active Feed",
        target_group: "updated-group"
      },
      enable_feed: "1"
    }

    assert_redirected_to feed_path(enabled_feed)
    follow_redirect!
    assert_match "Changes will take effect on the next scheduled refresh", response.body
  end

  test "#update should render edit form with errors on validation failure" do
    sign_in_as(user)

    patch feed_url(feed), params: {
      feed: {
        target_group: "INVALID GROUP!"
      }
    }

    assert_response :unprocessable_entity
    assert_select "form"
  end

  test "#update should not require a preview for operational-only edits on enabled feed" do
    sign_in_as(user)
    enabled_feed = create(:feed,
                          user: user,
                          state: :enabled,
                          access_token: access_token,
                          target_group: "tg",
                          feed_profile_key: "rss",
                          params: { "url" => "http://example.com/feed.xml" })

    patch feed_url(enabled_feed), params: { feed: { name: "Renamed Feed" }, enable_feed: "1" }

    assert_redirected_to feed_path(enabled_feed)
    enabled_feed.reload
    assert_equal "Renamed Feed", enabled_feed.name
    assert_equal "enabled", enabled_feed.state
  end

  test "#update should not allow changing url or feed_profile_key" do
    sign_in_as(user)
    original_url = feed.url
    original_profile = feed.feed_profile_key
    original_params = feed.params

    patch feed_url(feed), params: {
      feed: {
        url: "https://evil.com/feed.xml",
        feed_profile_key: "xkcd",
        params: { url: "https://evil.com/feed.xml", smuggled: "yes" },
        name: "Updated Name"
      }
    }

    assert_redirected_to feed_path(feed)
    feed.reload
    assert_equal original_url, feed.url
    assert_equal original_profile, feed.feed_profile_key
    assert_equal original_params, feed.params, "raw params jsonb must not be mass-assignable on update"
    assert_equal "Updated Name", feed.name
  end

  test "#update should permit url change when feed is draft" do
    sign_in_as(user)
    draft = create(:feed, :draft, user: user)
    new_url = "https://example.com/new-feed.xml"

    patch feed_url(draft), params: { feed: { params: { url: new_url } } }

    draft.reload
    assert_equal new_url, draft.url
  end

  test "#update should ignore url change when feed is disabled" do
    sign_in_as(user)
    disabled = create(:feed, :disabled, user: user,
                      params: { "url" => "https://original.com/feed.xml" })

    patch feed_url(disabled), params: { feed: { params: { url: "https://attacker.com/feed.xml" } } }

    disabled.reload
    assert_equal "https://original.com/feed.xml", disabled.url
  end

  test "#update should reset schedule next_run_at when interval changes" do
    sign_in_as(user)
    enabled_feed = create(:feed, user: user, state: :enabled, access_token: access_token)
    enabled_feed.create_feed_schedule!(next_run_at: 12.hours.from_now, last_run_at: Time.current)
    old_next_run = enabled_feed.feed_schedule.next_run_at

    patch feed_url(enabled_feed), params: {
      feed: {
        schedule_interval: "10m"
      },
      enable_feed: "1"
    }

    assert_redirected_to feed_path(enabled_feed)
    enabled_feed.reload
    assert_equal "10m", enabled_feed.schedule_interval
    assert_operator enabled_feed.feed_schedule.next_run_at, :<, old_next_run
    assert_in_delta Time.current, enabled_feed.feed_schedule.next_run_at, 5.seconds
  end

  test "#update should not allow direct cron_expression updates" do
    sign_in_as(user)
    feed.update!(schedule_interval: "1h")
    original_cron = feed.cron_expression

    patch feed_url(feed), params: {
      feed: {
        cron_expression: "0 0 * * *",
        name: "Updated Name"
      }
    }

    assert_redirected_to feed_path(feed)
    feed.reload
    assert_equal original_cron, feed.cron_expression
    assert_equal "Updated Name", feed.name
  end

  test "#update should promote a draft to enabled when checkbox checked and valid" do
    sign_in_as(user)
    draft = create(:feed, :draft, user: user, access_token: access_token,
                                  target_group: "tg",
                                  feed_profile_key: "rss",
                                  params: { "url" => "http://example.com/feed.xml" })

    patch feed_url(draft), params: {
      feed: { name: "Promoted Feed" },
      enable_feed: "1"
    }

    assert_redirected_to feed_path(draft)
    draft.reload
    assert_predicate draft, :enabled?
    assert_equal "Promoted Feed", draft.name
  end

  test "#update should keep a disabled feed disabled when enable-validation fails" do
    sign_in_as(user)
    disabled = create(:feed, :disabled, user: user, access_token: access_token,
                                        target_group: "tg",
                                        feed_profile_key: "rss",
                                        params: { "url" => "http://example.com/feed.xml" })

    # Clear target_group to force an enable-side validation failure
    # (target_group is required only when a feed is enabled).
    patch feed_url(disabled), params: {
      feed: { target_group: "" },
      enable_feed: "1"
    }

    assert_response :unprocessable_entity
    disabled.reload
    assert_predicate disabled, :disabled?, "Disabled feed must not fall back to draft"
    assert_match "Couldn't enable", flash[:alert]
    assert_select "#target-group-selector p.text-red-600", text: /can(?:'|&#39;)t be blank/
  end

  test "#update should pause an enabled feed when checkbox unchecked" do
    sign_in_as(user)
    enabled_feed = create(:feed, :enabled, user: user, access_token: access_token)

    patch feed_url(enabled_feed), params: { feed: { name: "Paused Feed" } }

    assert_redirected_to feed_path(enabled_feed)
    enabled_feed.reload
    assert_predicate enabled_feed, :disabled?
    assert_equal "Paused Feed", enabled_feed.name
  end

  test "#update should record a feed_enabled event when promoting a draft" do
    sign_in_as(user)
    draft = create(:feed, :draft, user: user, access_token: access_token,
                                  target_group: "tg",
                                  feed_profile_key: "rss",
                                  params: { "url" => "http://example.com/feed.xml" })

    assert_difference("Event.where(type: 'feed_enabled', subject: draft).count", 1) do
      patch feed_url(draft), params: { feed: { name: "Promoted Feed" }, enable_feed: "1" }
    end
  end

  test "#update should record a feed_disabled event when pausing a feed" do
    sign_in_as(user)
    enabled_feed = create(:feed, :enabled, user: user, access_token: access_token)

    assert_difference("Event.where(type: 'feed_disabled', subject: enabled_feed).count", 1) do
      patch feed_url(enabled_feed), params: { feed: { name: "Paused Feed" } }
    end
  end

  test "#create should record a feed_enabled event when enabling on creation" do
    sign_in_as(user)

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "New Feed",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h"
    }

    assert_difference("Event.where(type: 'feed_enabled').count", 1) do
      post feeds_path, params: { feed: feed_params, enable_feed: "1" }
    end
  end

  test "#update should save and redirect to token setup when commit signals token gate" do
    sign_in_as(user)
    draft = create(:feed, :draft, user: user)

    patch feed_url(draft), params: {
      feed: { name: "Updated Draft Name" },
      commit: "save_as_draft_and_add_token"
    }

    assert_redirected_to new_access_token_path(feed_id: draft.id)
    draft.reload
    assert_predicate draft, :draft?
    assert_equal "Updated Draft Name", draft.name
  end

  test "#update should save and redirect to credential setup when commit signals gate" do
    sign_in_as(user)
    draft = create(:feed, :draft, user: user)

    patch feed_url(draft), params: {
      feed: { name: "Updated Draft Name" },
      commit: "save_as_draft_and_add_credentials"
    }

    assert_redirected_to new_llm_credential_path(feed_id: draft.id)
    draft.reload
    assert_predicate draft, :draft?
    assert_equal "Updated Draft Name", draft.name
  end

  test "#update should save changes to a draft without enabling" do
    sign_in_as(user)
    draft = create(:feed, :draft, user: user)

    patch feed_url(draft), params: { feed: { name: "Updated Draft" } }

    assert_redirected_to feed_path(draft)
    draft.reload
    assert_predicate draft, :draft?
    assert_equal "Updated Draft", draft.name
  end

  test "#create should re-render the expanded form with a manual preview button and no auto-loading frame" do
    sign_in_as(user)
    access_token

    post feeds_path, params: {
      feed: {
        url: "http://example.com/feed.xml",
        name: "Test Feed",
        feed_profile_key: "rss",
        access_token_id: access_token.id,
        target_group: "INVALID GROUP!",
        schedule_interval: "1h"
      },
      enable_feed: "0"
    }

    assert_response :unprocessable_entity
    assert_select "[data-key='preview.open']", count: 1
    assert_select "turbo-frame#feed-preview[loading='lazy']", count: 0
    assert_select "turbo-frame#feed-preview[src]", count: 0
  end

  test "#edit should render a manual preview button" do
    sign_in_as(user)
    feed = create(:feed, :disabled, user: user, access_token: access_token,
                                     feed_profile_key: "rss",
                                     params: { "url" => "http://example.com/feed.xml" })

    get edit_feed_path(feed)

    assert_response :success
    assert_select "[data-key='preview.open']", count: 1
    # The preview-button controller must wrap BOTH the profile field and the
    # button, or it can't read the selected feed_profile_key at click time.
    assert_select "#feed-form[data-controller~='preview-button'] [data-key='preview.open']", count: 1
    assert_select "#feed-form[data-controller~='preview-button'] input[name='feed[feed_profile_key]']", count: 1
  end

  test "#destroy should remove own feed" do
    sign_in_as(user)
    feed = create(:feed, user: user)

    assert_difference("Feed.count", -1) do
      delete feed_url(feed)
    end

    assert_redirected_to feeds_url
  end

  test "#destroy should not remove other user's feed" do
    sign_in_as(user)
    delete feed_url(other_feed)
    assert_response :not_found
  end














  test "#index should sort feeds by name" do
    sign_in_as(user)
    create(:feed, user: user, name: "Z Feed")
    create(:feed, user: user, name: "A Feed")

    get feeds_url(sort: "name", direction: "asc")
    assert_response :success

    response_body = response.body
    pos_a = response_body.index("A Feed")
    pos_z = response_body.index("Z Feed")
    assert pos_a < pos_z, "Expected A Feed to appear before Z Feed"
  end

  test "#index should sort feeds by status as draft, enabled, disabled when ascending" do
    sign_in_as(user)
    create(:feed, :enabled, user: user, name: "Enabled Feed")
    create(:feed, user: user, name: "Disabled Feed", state: :disabled)
    create(:feed, user: user, name: "Draft Feed", state: :draft)

    get feeds_url(sort: "status", direction: "asc")
    assert_response :success

    response_body = response.body
    pos_draft = response_body.index("Draft Feed")
    pos_enabled = response_body.index("Enabled Feed")
    pos_disabled = response_body.index("Disabled Feed")
    assert_not_nil pos_draft, "Expected draft feed to be rendered"
    assert_not_nil pos_enabled, "Expected enabled feed to be rendered"
    assert_not_nil pos_disabled, "Expected disabled feed to be rendered"
    assert pos_draft < pos_enabled, "Expected draft feed to appear before enabled feed"
    assert pos_enabled < pos_disabled, "Expected enabled feed to appear before disabled feed"
  end

  test "#index should sort feeds by status as disabled, enabled, draft when descending" do
    sign_in_as(user)
    create(:feed, :enabled, user: user, name: "Enabled Feed")
    create(:feed, user: user, name: "Disabled Feed", state: :disabled)
    create(:feed, user: user, name: "Draft Feed", state: :draft)

    get feeds_url(sort: "status", direction: "desc")
    assert_response :success

    response_body = response.body
    pos_draft = response_body.index("Draft Feed")
    pos_enabled = response_body.index("Enabled Feed")
    pos_disabled = response_body.index("Disabled Feed")
    assert_not_nil pos_draft, "Expected draft feed to be rendered"
    assert_not_nil pos_enabled, "Expected enabled feed to be rendered"
    assert_not_nil pos_disabled, "Expected disabled feed to be rendered"
    assert pos_disabled < pos_enabled, "Expected disabled feed to appear before enabled feed"
    assert pos_enabled < pos_draft, "Expected enabled feed to appear before draft feed"
  end

  test "#pagination should preserve sort parameters" do
    sign_in_as(user)
    3.times { |i| create(:feed, user: user, name: "Feed #{i}") }

    get feeds_url(sort: "name", direction: "desc", per_page: 2)
    assert_response :success
    assert_select "nav[aria-label='Feeds pagination'] a[href*='sort=name']"
    assert_select "nav[aria-label='Feeds pagination'] a[href*='direction=desc']"
  end
end
