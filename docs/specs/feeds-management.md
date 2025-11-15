# Feed CRUD Requirements Specification

## Overview

Implement create, edit, and delete functionality for Feed records in the Feeder application. This feature allows users to configure feed sources, identify feed profiles, and set up automated content reposting to FreeFeed groups.

## Current State

### Existing Implementation

- [x] Feed model with comprehensive validations
- [x] Feed profile system (RSS, XKCD) with ProfileMatcher
- [x] TitleExtractor for RSS feeds
- [x] Feed scheduling via FeedSchedulerJob and cron expressions
- [x] AccessToken model with FreeFeed integration
- [x] Feeds index and show pages
- [x] Feed enable/disable via FeedStatusesController
- [x] Feed deletion functionality

### To Be Implemented

- [ ] Feed creation flow with async profile identification
- [ ] Feed editing form
- [ ] `FeedsController#create` and `#update` actions
- [ ] `FeedDetailsController` for async identification (create and show actions)
- [ ] `FeedIdentificationJob` background job
- [ ] Groups API endpoint for token-based group fetching
- [ ] Client-side form dynamics (Stimulus controllers)



## Feature Requirements

### 1. Feed Creation Flow

#### 1.1 Entry Point

- **Location**: Feeds index page (`/feeds`)
- **Trigger**: "New Feed" button (already exists)
- **Destination**: `/feeds/new` (GET)

#### 1.2 Initial Form State (Collapsed)

**Prerequisite Check**: Before displaying the form, verify the user has at least one active access token.

**If NO active tokens exist**:
- Display blocked state message: "You need to add an active FreeFeed access token before creating a feed."
- Show prominent link/button: "Add Access Token" (links to `/settings/access_tokens/new`)
- Do NOT show the URL input or Identify button
- This prevents users from going through identification only to discover they can't complete the form

**If active tokens exist**:
When the user lands on `/feeds/new`, display:
- **URL Input**: Text field for feed URL
  - Label: "Feed URL"
  - Placeholder: "https://example.com/feed.xml"
  - Accepts any valid HTTP/HTTPS URL
  - Required field
- **Identify Button**: Primary action button
  - Label: "Identify Feed Format"
  - Triggers profile identification

#### 1.3 Initiate Profile Identification Process

**Endpoint**: `POST /feeds/details` (`FeedDetailsController#create` starts identification process)

**Request Parameters**:
- `url`: The feed URL to identify

**Cache Strategy**:
- **Cache Key**: `"feed_identification/#{current_user.id}/#{Digest::SHA256.hexdigest(url)}"`
- **TTL**: 10 minutes
- **Reuse**: If cache entry exists, reuse it and do not enqueue background job
- **Data Structure**:
  ```ruby
  {
    status: "processing" | "success" | "failed",
    url: "original_url",
    feed_profile_key: "rss" (if success),
    title: "extracted_title" (if success, can be nil),
    error: "error_message" (if failed)
  }
  ```

**Server-side Process**:
1. Generate cache key from `current_user.id` and URL
2. Check if cache entry exists:
   - If exists: Return current status (don't enqueue new job)
   - If not exists: Create cache entry with `status: "processing"`
3. Enqueue `FeedIdentificationJob` with user_id and URL
4. Return Turbo Stream response, switching the page to "Loading" state (see `FeedPreviewsController` for an example)

**Background Job (`FeedIdentificationJob`)**:
1. Receive `user_id` and `url` as parameters
2. Validate URL format (HTTP/HTTPS)
3. Fetch feed data from the HTTP URL
4. Run `FeedProfileDetector.detect(url, response)`
5. If profile matched:
   - Run appropriate `TitleExtractor` for the profile
   - Extract feed title
   - Update cache with `status: "success"`, `feed_profile_key`, and `title`
6. If profile not matched or error occurred:
   - Update cache with `status: "failed"` and error message

#### 1.4 Poll for the Profile Identification Result

**Endpoint**: `GET /feeds/details` (`FeedDetailsController#show` responds to polling for the identification results)

**Request Parameters**:
- `url`: The feed URL used to generate the cache key

**Polling Implementation**:
- Uses existing `polling_controller.js` Stimulus controller
- Poll interval: 2 seconds (default)
- Maximum polls: 30 attempts = 60 seconds total (default)
- Automatically handles:
  - Network errors (continues polling)
  - Offline mode (pauses polling when `navigator.onLine` is false)
  - Non-OK HTTP responses (stops polling)
  - Aborts previous request if new poll starts
- Stop condition: `[data-identification-state="complete"]` or `[data-identification-state="error"]`

**Server-side Process**:
1. Generate cache key from `current_user.id` and URL
2. Fetch data from Rails cache
3. Based on status, return appropriate Turbo Stream response

**Success Response** (Turbo Stream, when `status: "success"`):
- Replace form with expanded version including:
  - Identified profile
  - Extracted title (or empty if extraction failed)
  - All configuration fields
  - **Hidden fields**: `url`, `feed_profile_key`, `name` (from cache)
- Add `data-identification-state="complete"` attribute to container to trigger polling stop condition
- **Stop polling** - identification complete

**Processing Response** (Turbo Stream, when `status: "processing"`):
- Keep polling state active with loading indicator
- **Continue polling** via Turbo Stream refresh until status changes
- After 30 polls (60 seconds), polling automatically stops and shows timeout state

**Failure Response** (Turbo Stream, when `status: "failed"`):
- Show inline error message in form
- Keep URL field populated for editing
- Error message: "We couldn't identify a feed profile for this URL. Please check the URL and try again, or try a different feed source."
- Add `data-identification-state="error"` attribute to container to trigger polling stop condition
- **Stop polling** - identification failed

**Timeout Handling**:
If 30 polls complete without success/failure (cache stuck in "processing"):
- Polling automatically stops (handled by polling_controller)
- Show timeout error state via Turbo Stream
- Error message: "Feed identification is taking longer than expected. The feed URL may not be responding. Please try again."
- Provide "Try Again" button

**No Manual Profile Override**: If identification fails, users must try a different URL. No dropdown to manually select profiles.

#### 1.5 Expanded Form State

After successful identification, show:

**1. URL (Read-only)**
- Display as disabled text input (grayed out, see current email field at `app/views/settings/email_updates/edit.html.erb` for example)
- Label: "Feed URL"
- Hidden field: `f.hidden_field :url` (controller uses this, not cache)

**2. Identified Profile (Read-only)**
- Display as static text field styled like form input
- Show profile name in human-readable format (e.g., "RSS Feed")
- Label: "Feed Type"
- Hidden field: `f.hidden_field :feed_profile_key` (controller uses this, not cache)

**3. Feed Title (Editable)**
- Text input pre-filled with extracted title from identification
- User can modify
- Label: "Feed Name"
- Validation: Required, max 40 chars, unique within user's scope
- Help text: "This name will be displayed in your feeds list"
- Value comes from identification result, not cache (passed via locals)

**4. Reposting Configuration Section**
Section header: "Reposting Settings"

**4.1 Access Token Selector**
- Dropdown select
- Label: "FreeFeed Account"
- Shows only active tokens for current user
- Display format: `{host_domain} - {owner}` (e.g., "freefeed.net - username")
- Uses `AccessToken.active.where(user: current_user)`
- Required field
- Note: User is guaranteed to have at least one active token (verified in section 1.2)
- When changed:
  - Immediately disable token selector (prevent race conditions)
  - Trigger Turbo Stream request: `GET /access_tokens/:id/groups`
  - Re-render target group selector with loading state
  - Re-enable token selector after groups loaded
- Implemented via `data-action="change->groups-loader#loadGroups"` on select

**4.2 Target Group Selector**
- Initially: Disabled select with placeholder "Select a FreeFeed account first"
- Label: "Target Group"
- Dynamically re-rendered via Turbo Stream when access token is selected
- Fetches from: `GET /access_tokens/:id/groups` (returns Turbo Stream)
- Display format: Group name as shown in FreeFeed API
- Required field

**Loading State** (while fetching groups):
- Select element remains visible with disabled state
- First option shows "Loading groups..." as placeholder
- Select is disabled (`disabled="disabled"`)
- This prevents form submission while groups are loading

**Success State** (groups fetched):
- Regular select dropdown with fetched groups as options
- Select is enabled
- Groups displayed in alphabetical order
- Pre-selects current feed's target_group if editing

**Error/Fallback State** (groups loading failed):
- Text input replaces select dropdown
- Help text: "Could not load groups. Enter the group name manually."
- Validation: Lowercase letters, numbers, underscores, dashes only; max 80 chars
- Pre-fills current feed's target_group if editing

**General Help Text**: "The FreeFeed group where posts will be published"

**4.3 Groups Endpoint Implementation**
`GET /access_tokens/:id/groups`

**Logic**:
1. Lookup access token by ID (scoped to `current_user`)
2. If token found and active: fetch groups from FreeFeed API (with 10-minute cache)
3. If token not found, inactive, or API fails: return empty groups array
4. Return Turbo Stream that replaces the target group selector partial

**Response**: Turbo Stream that renders `_target_group_selector.html.erb` partial with:
- If groups fetched successfully: Select dropdown with groups as options
- If groups fetch failed: Text input for manual entry
- Current feed's target_group value pre-selected/pre-filled (for edit mode)

**Error Handling**:
- Token not found or doesn't belong to user → render empty selector with text input fallback
- FreeFeed API error → render empty selector with text input fallback (logged)
- Token inactive → render empty selector with text input fallback
- All cases gracefully degrade to manual text entry instead of breaking the form

**5. Feed Refresh Schedule Section**
Section header: "Refresh Schedule"

**5.1 Schedule Interval Selector**
- Dropdown select
- Label: "Check for new posts every"
- Options: 10m, 20m, 30m, 1h, 2h, 6h, 12h, 1d, 2d
- Display format: Human-readable (e.g., "10 minutes", "1 hour", "2 days")
- Default: 1h
- Required field

**5.2 Schedule Intervals Configuration**
Define in Feed model:
```ruby
SCHEDULE_INTERVALS = {
  "10m" => { cron: "*/10 * * * *", display: "10 minutes" },
  "20m" => { cron: "*/20 * * * *", display: "20 minutes" },
  "30m" => { cron: "*/30 * * * *", display: "30 minutes" },
  "1h" => { cron: "0 * * * *", display: "1 hour" },
  "2h" => { cron: "0 */2 * * *", display: "2 hours" },
  "6h" => { cron: "0 */6 * * *", display: "6 hours" },
  "12h" => { cron: "0 */12 * * *", display: "12 hours" },
  "1d" => { cron: "0 0 * * *", display: "1 day" },
  "2d" => { cron: "0 0 */2 * *", display: "2 days" }
}.freeze
```

**Helper methods**:
- `Feed.schedule_intervals_for_select`: Returns array for dropdown
- `Feed#schedule_interval`: Returns display key (e.g., "1h") from cron
- `Feed#schedule_interval=(key)`: Sets cron_expression from key

**6. Feed State Configuration**
- Checkbox input (checked by default)
- Label: "Enable this feed immediately after creation"
- Help text: "Enabled feeds will automatically check for new posts and publish them to FreeFeed"
- If unchecked: Feed is created with `state: :disabled`
- If checked: Feed is created with `state: :enabled` (must pass `can_be_enabled?` validation)

**Validation Behavior**:
- If checkbox is checked but feed doesn't pass `can_be_enabled?`:
  - Show validation error
  - Keep user on form with all data intact
  - Error message lists missing requirements (using existing `feed_missing_enablement_parts` helper)

**7. Form Submission**
- Button label dynamically reflects state:
  - If enable checkbox checked: "Create and Enable Feed"
  - If enable checkbox unchecked: "Create Feed"
- On success: Redirect to feed show page (`/feeds/:id`)
- Flash message: "Feed '{name}' was successfully created."
- If enabled: Additional message: "Your feed is now active and will check for new posts {schedule_display}."

#### 1.6 Temporary Cache Storage During Identification

**Critical**: Profile identification uses Rails cache for temporary storage (10 minute TTL). No Feed database records are created during identification. All identified data (URL, profile, title) are passed as form parameters when the user submits the final create button. Cache entries are scoped by user_id to prevent data leakage between users.



### 2. Feed Editing Flow

#### 2.1 Entry Point

- **Location**: Feed show page (`/feeds/:id`)
- **Trigger**: "Edit" button/link
- **Destination**: `/feeds/:id/edit` (GET)

#### 2.2 Edit Form Layout

The edit form is identical to the expanded create form with these differences:

**Read-only Fields** (cannot be changed):
1. **URL**: Displayed as plain text with hidden input
   - Shows the feed's current URL
   - Style: Same as expanded create form (looks like disabled input)

2. **Feed Profile**: Displayed as plain text with hidden input
   - Shows current profile in human-readable format
   - Cannot be changed after creation

**Editable Fields** (same as create):
1. Feed Title (name)
2. Access Token selector
3. Target Group selector (updates when token changes)
4. Refresh Schedule interval

**Feed State** (different from create):
- **No checkbox**: State is controlled via separate enable/disable buttons on show page
- The edit form does NOT change feed state
- If feed is currently enabled, attempting to save invalid configuration that breaks `can_be_enabled?` should show validation error

#### 2.3 Form Submission

- Button label: "Update Feed Configuration"
- On success: Redirect to feed show page
- Flash message: "Feed '{name}' was successfully updated."
- If feed is enabled and configuration changed: Additional message: "Changes will take effect on the next scheduled refresh."

#### 2.4 Concurrent Edits

**Approach**: Last-write-wins (no locking)

**Rationale**:
- Low contention: Single user editing their own feeds
- Edit form doesn't change `state` (handled via separate enable/disable actions)
- Short transaction time (~50ms for UPDATE)
- Acceptable risk: User overwrites their own recent changes

**Edge Cases**:
- If background job disables feed while user is editing: User's update will succeed, but feed remains disabled (state is not changed via edit form)
- If user edits same feed in multiple tabs: Last save wins



### 3. Feed Deletion

**Current Implementation**: Already exists via `DELETE /feeds/:id`
- Triggered from show page "Delete Feed" button in danger zone
- Confirmation modal required
- Cascading deletes: feed_schedule, events, feed_entries, feed_metrics, posts

**No changes required** to deletion flow.



## Technical Implementation Details

### Database Changes

No database migrations needed for feed CRUD functionality. All required columns already exist in the feeds table.

### Routing Changes

Add to `config/routes.rb`:
```ruby
# Feeds CRUD routes already exist with status and purge nested resources
# Only add the new feed details resource:
resource :feed_details, only: [:create, :show], path: 'feeds/details'

# Add groups endpoint to existing access_tokens routes:
resources :access_tokens, only: [] do
  member do
    get :groups # Fetch groups for token
  end
end
```

### Controller Actions

#### FeedsController#new

```ruby
def new
  @feed = current_user.feeds.build
  @has_active_tokens = current_user.access_tokens.active.exists?

  # View will check @has_active_tokens and show either:
  # - Blocked state with "Add Access Token" link if false
  # - Normal form if true
end
```

#### FeedsController#create

```ruby
def create
  @feed = current_user.feeds.build(feed_params)

  if params[:enable_feed] == "1"
    @feed.state = :enabled
  end

  if @feed.save
    redirect_to @feed, notice: success_message
  else
    render :new, status: :unprocessable_entity
  end
end

private

def feed_params
  params.require(:feed).permit(:url, :feed_profile_key, :name, :access_token_id, :target_group, :schedule_interval)
end
```

**Important**: Controller uses form params (from hidden fields), NOT cached identification data. This ensures:
- Form submission works even if cache expires (>10 minutes)
- No dependency on Rails.cache during create
- All data explicitly submitted by user

#### FeedsController#edit

```ruby
def edit
  @feed = current_user.feeds.find(params[:id])
end
```

#### FeedsController#update

```ruby
def update
  @feed = current_user.feeds.find(params[:id])

  if @feed.update(feed_params)
    redirect_to @feed, notice: "Feed '#{@feed.name}' was successfully updated."
  else
    render :edit, status: :unprocessable_entity
  end
end
```

#### FeedDetailsController#create (NEW)

```ruby
def create
  url = params[:url]

  # Validate URL format
  unless url.present? && url.match?(URI::DEFAULT_PARSER.make_regexp(%w[http https]))
    return render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/identification_error",
      locals: { url: url, error: "Please enter a valid URL" }
    )
  end

  cache_key = feed_identification_cache_key(url)

  # Check if identification already in progress or completed
  cached_data = Rails.cache.read(cache_key)

  if cached_data.nil?
    # Create cache entry with processing status
    Rails.cache.write(
      cache_key,
      { status: "processing", url: url, started_at: Time.current },
      expires_in: 10.minutes
    )

    # Enqueue background job
    FeedIdentificationJob.perform_later(current_user.id, url)
  end

  # Return loading state (polls via show action)
  render turbo_stream: turbo_stream.replace(
    "feed-form",
    partial: "feeds/identification_loading",
    locals: { url: url }
  )
end

private

def feed_identification_cache_key(url)
  "feed_identification/#{current_user.id}/#{Digest::SHA256.hexdigest(url)}"
end
```

**Rate Limiting**:
- Limit identification requests to **10 per hour per user**
- Prevents job queue flooding from malicious or accidental spam
- Returns 429 Too Many Requests if limit exceeded
- Error message: "Too many identification attempts. Please wait before trying again."

#### FeedDetailsController#show (NEW)

```ruby
def show
  url = params[:url]
  cache_key = feed_identification_cache_key(url)
  cached_data = Rails.cache.read(cache_key)

  if cached_data.nil?
    # Cache expired or never existed
    return render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/identification_error",
      locals: { url: url, error: "Identification session expired. Please try again." }
    )
  end

  case cached_data[:status]
  when "processing"
    # Check if processing for too long (job may have crashed/stuck)
    started_at = cached_data[:started_at] || Time.current
    timeout_threshold = 90.seconds

    if Time.current - started_at > timeout_threshold
      # Job timed out - clean up stuck cache entry and show error
      Rails.cache.delete(cache_key)
      return render turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/identification_error",
        locals: {
          url: url,
          error: "Feed identification timed out. The feed may not be responding. Please try again."
        }
      )
    end

    # Still processing normally
    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/identification_loading",
      locals: { url: url }
    )
  when "success"
    # Build feed object with identified data
    @feed = current_user.feeds.build(
      url: cached_data[:url],
      feed_profile_key: cached_data[:feed_profile_key],
      name: cached_data[:title]
    )

    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/form_expanded",
      locals: { feed: @feed }
    )
  when "failed"
    # Identification failed
    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/identification_error",
      locals: { url: url, error: cached_data[:error] || "We couldn't identify a feed profile for this URL." }
    )
  end
end

private

def feed_identification_cache_key(url)
  "feed_identification/#{current_user.id}/#{Digest::SHA256.hexdigest(url)}"
end
```

#### AccessTokensController#groups (NEW)

```ruby
class AccessTokensController < ApplicationController
  def groups
    @token = current_user.access_tokens.find_by(id: params[:id])
    @feed = current_user.feeds.find_by(id: params[:feed_id]) || current_user.feeds.build

    # Use find_by instead of find - if token not found or doesn't belong to user,
    # gracefully render empty selector (better UX for Turbo Stream context)
    @groups = if @token&.active?
      fetch_groups_with_cache(@token)
    else
      []
    end

    render turbo_stream: turbo_stream.replace(
      "target-group-selector",
      partial: "feeds/target_group_selector",
      locals: { feed: @feed, groups: @groups, token: @token }
    )
  end

  private

  def fetch_groups_with_cache(token)
    Rails.cache.fetch(
      "access_token_groups/#{token.id}",
      expires_in: 10.minutes,
      race_condition_ttl: 5.seconds
    ) do
      fetch_groups_from_freefeed(token)
    end
  rescue => e
    # FreeFeed API error - cache failure with shorter TTL to prevent hammering
    Rails.logger.error("Failed to fetch groups for token #{token.id}: #{e.message}")

    # Cache empty result for 1 minute to prevent repeated API calls
    Rails.cache.write(
      "access_token_groups/#{token.id}",
      [],
      expires_in: 1.minute
    )

    []
  end

  def fetch_groups_from_freefeed(token)
    client = token.build_client
    client.managed_groups.map(&:username) # Returns array of group names
  end
end
```

### Background Jobs

#### FeedIdentificationJob (NEW)

```ruby
class FeedIdentificationJob < ApplicationJob
  queue_as :default

  def perform(user_id, url)
    user = User.find(user_id)
    cache_key = "feed_identification/#{user_id}/#{Digest::SHA256.hexdigest(url)}"

    begin
      # Fetch feed data
      response = http_client.get(url)

      # Identify profile
      profile_key = FeedProfileDetector.detect(url, response)

      if profile_key
        # Extract title
        title_extractor = FeedProfile.title_extractor_class_for(profile_key).new(url, response)
        title = title_extractor.title rescue nil

        # Update cache with success
        Rails.cache.write(
          cache_key,
          {
            status: "success",
            url: url,
            feed_profile_key: profile_key,
            title: title
          },
          expires_in: 10.minutes
        )
      else
        # Update cache with failure
        Rails.cache.write(
          cache_key,
          {
            status: "failed",
            url: url,
            error: "Could not identify feed profile"
          },
          expires_in: 10.minutes
        )
      end
    rescue => e
      Rails.logger.error("Feed identification failed for #{url}: #{e.message}")
      Rails.cache.write(
        cache_key,
        {
          status: "failed",
          url: url,
          error: "An error occurred while identifying the feed"
        },
        expires_in: 10.minutes
      )
    end
  end

  private

  def http_client
    @http_client ||= HttpClient.build
  end
end
```

### Model Changes

#### Feed Model - Schedule Interval Mapping

```ruby
SCHEDULE_INTERVALS = {
  "10m" => { cron: "*/10 * * * *", display: "10 minutes" },
  "20m" => { cron: "*/20 * * * *", display: "20 minutes" },
  "30m" => { cron: "*/30 * * * *", display: "30 minutes" },
  "1h" => { cron: "0 * * * *", display: "1 hour" },
  "2h" => { cron: "0 */2 * * *", display: "2 hours" },
  "6h" => { cron: "0 */6 * * *", display: "6 hours" },
  "12h" => { cron: "0 */12 * * *", display: "12 hours" },
  "1d" => { cron: "0 0 * * *", display: "1 day" },
  "2d" => { cron: "0 0 */2 * *", display: "2 days" }
}.freeze

def self.schedule_intervals_for_select
  SCHEDULE_INTERVALS.map { |key, config| [config[:display], key] }
end

def schedule_interval
  SCHEDULE_INTERVALS.find { |_key, config| config[:cron] == cron_expression }&.first
end

def schedule_interval=(key)
  self.cron_expression = SCHEDULE_INTERVALS.dig(key, :cron)
end

def schedule_display
  SCHEDULE_INTERVALS.dig(schedule_interval, :display) || cron_expression
end
```

#### Feed Model - Validations

**Uniqueness Constraint**:
- Validate `(user_id, url, target_group)` combination is unique
- Allows same URL to different groups (user may want to cross-post)
- Prevents duplicate feeds to the same destination
- Error message: "A feed with this URL and target group already exists"

**Access Token Ownership**:
- Validate `access_token` belongs to the feed's `user`
- Prevents malicious users from assigning someone else's token via crafted POST
- Checked on create and update
- Error message: "Access token is invalid"

**Schedule Interval**:
- Validate `schedule_interval` is a valid key in `SCHEDULE_INTERVALS` constant
- If invalid key provided, `cron_expression` becomes nil and validation fails
- Error message: "Schedule interval is not valid"

**Data Consistency for Feed Creation**:
- When creating enabled feed: wrap in transaction
- If feed saves but schedule creation fails, entire operation rolls back
- Ensures feed is never left in inconsistent state (enabled without schedule)
- User sees error and can retry with all data intact

### Stimulus Controllers

**Existing controllers used**:
- `polling_controller.js` - Handles async polling for feed identification results

**New controllers to implement**:

#### feed-identification-controller.js

Handles disabling Identify button and URL input to prevent double-submission:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submitButton", "urlInput"]

  // Turbo events
  disableForm(event) {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
    }
    if (this.hasUrlInputTarget) {
      this.urlInputTarget.disabled = true
    }
  }

  enableForm(event) {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = false
    }
    if (this.hasUrlInputTarget) {
      this.urlInputTarget.disabled = false
    }
  }
}
```

Usage in `_form_collapsed.html.erb`:
```erb
<%= form_with url: feed_details_path,
              data: {
                controller: "feed-identification",
                action: "turbo:submit-start->feed-identification#disableForm turbo:submit-end->feed-identification#enableForm"
              } do |f| %>
  <%= f.text_field :url, data: { feed_identification_target: "urlInput" } %>
  <%= f.submit "Identify Feed Format", data: { feed_identification_target: "submitButton" } %>
<% end %>
```

#### groups-loader-controller.js

Handles loading state for groups selector when token changes:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tokenSelect", "groupsContainer"]

  loadGroups(event) {
    // Disable token selector to prevent race conditions
    if (this.hasTokenSelectTarget) {
      this.tokenSelectTarget.disabled = true
    }

    // Show loading state in groups container immediately
    if (this.hasGroupsContainerTarget) {
      this.showLoadingState()
    }
  }

  showLoadingState() {
    // Render loading select immediately (before Turbo Stream response)
    this.groupsContainerTarget.innerHTML = `
      <select disabled class="form-select" name="feed[target_group]">
        <option>Loading groups...</option>
      </select>
    `
  }

  // Called after Turbo Stream replaces groups selector
  groupsLoaded(event) {
    // Re-enable token selector
    if (this.hasTokenSelectTarget) {
      this.tokenSelectTarget.disabled = false
    }
  }
}
```

Usage in `_form_expanded.html.erb`:
```erb
<div data-controller="groups-loader">
  <%= f.select :access_token_id,
               options_for_select(...),
               {},
               data: {
                 groups_loader_target: "tokenSelect",
                 action: "change->groups-loader#loadGroups"
               } %>

  <div id="target-group-selector"
       data-groups-loader-target="groupsContainer"
       data-action="turbo:frame-load->groups-loader#groupsLoaded">
    <%= render "target_group_selector", ... %>
  </div>
</div>
```

#### feed-form-controller.js

Handles submit button label updates based on enable checkbox:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["enableCheckbox", "submitButton"]

  connect() {
    this.updateSubmitButtonLabel()
  }

  updateSubmitButtonLabel() {
    if (!this.hasSubmitButtonTarget || !this.hasEnableCheckboxTarget) return

    const isEnabled = this.enableCheckboxTarget.checked
    const isNew = this.submitButtonTarget.dataset.mode === 'new'

    if (isNew) {
      this.submitButtonTarget.textContent = isEnabled ?
        'Create and Enable Feed' :
        'Create Feed'
    }
  }
}
```

### Form Partials Structure

**app/views/feeds/new.html.erb**:
```erb
<%= render "layouts/page_header", title: "New Feed" %>

<div class="ff-container-sm ff-my-8">
  <div id="feed-form">
    <%= render "form_collapsed" %>
  </div>
</div>
```

**app/views/feeds/edit.html.erb**:
```erb
<%= render "layouts/page_header", title: "Edit Feed" %>

<div class="ff-container-sm ff-my-8">
  <%= render "form_expanded", feed: @feed, edit_mode: true %>
</div>
```

**app/views/feeds/_form_collapsed.html.erb**:
- Initial identification form
- URL input + Identify button

**app/views/feeds/_form_expanded.html.erb**:
- Full form with all fields
- Used after identification succeeds and for edit mode
- Handles read-only URL/profile for edit
- Has `data-identification-state="complete"` attribute (triggers polling stop condition)
- Includes hidden fields: `url`, `feed_profile_key`, `name` (from identification)
- Includes target group selector with `id="target-group-selector"`
- Uses `data-controller="groups-loader"` for token/groups interaction

**app/views/feeds/_target_group_selector.html.erb**:
- Partial for target group selector (dynamically re-rendered via Turbo Stream)
- Wrapped in `<div id="target-group-selector">`
- **If groups present**: Shows regular `<select>` dropdown with fetched groups as options
- **If no groups or error**: Shows `<input type="text">` with help text about manual entry
- Accepts current feed's target_group value for pre-selection/pre-fill
- Help text displayed below the field explaining the current state

**app/views/feeds/_identification_loading.html.erb**:
- Loading state during async identification
- Shows loading indicator (spinner + text)
- Uses `polling_controller` to poll `GET /feeds/details?url=<url>`
- Poll interval: 2 seconds, max 30 polls (60 seconds)
- Stops when element with `data-identification-state="complete"` or `data-identification-state="error"` appears in DOM
- Example structure:
```erb
<div class="feed-form-loading"
     data-controller="polling"
     data-polling-endpoint-value="<%= feed_details_path(url: url) %>"
     data-polling-interval-value="2000"
     data-polling-max-polls-value="30"
     data-polling-stop-condition-value="[data-identification-state='complete'], [data-identification-state='error']">
  <div class="flex items-center justify-center py-8">
    <div class="spinner mr-3"></div>
    <p class="text-gray-600">Identifying feed format...</p>
  </div>
</div>
```

**app/views/feeds/_identification_error.html.erb**:
- Error state after failed identification
- Shows error message and URL input for retry
- Has `data-identification-state="error"` attribute (triggers polling stop condition)
- Provides "Try Again" button to restart process

**app/views/feeds/_blocked_no_tokens.html.erb**:
- Blocked state when user has no active access tokens
- Shows message: "You need to add an active FreeFeed access token before creating a feed."
- Prominent "Add Access Token" button/link to `/settings/access_tokens/new`
- Prevents frustration of going through identification only to be blocked later

### Form Field Considerations

**Access Token Selector**:
- Always has at least one token available (prerequisite check in section 1.2)
- Dropdown populated with active tokens only
- Disabled during groups loading (managed by groups-loader Stimulus controller)
- Triggers Turbo Stream request on change via `data-action="change->groups-loader#loadGroups"`

**Target Group Selector**:
- Standard select dropdown when groups are available
- Falls back to text input when groups can't be loaded (error state)
- Dynamically updated via Turbo Stream when token changes
- Disabled during loading with "Loading groups..." placeholder
- Never stuck disabled: Turbo Stream always responds (success or error fallback)

**Schedule Interval Selector**:
- Standard select dropdown
- Human-readable labels, cron values hidden

### JavaScript Requirements

This feature requires JavaScript to be enabled:
- **Turbo**: For async form submission, streaming updates, and polling
- **Stimulus**: For form interactions (button disabling, loading states, label updates)
- **No fallback**: JavaScript is a base application requirement
- Users with JavaScript disabled will see non-functional forms

**Browser Support**:
- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+
- IE11 and older browsers not supported

**Polyfills**: None required for target browsers (all support Fetch API, ES6+)

### Validation Error Display

Follow existing pattern from AccessToken forms:
- Inline errors below each field
- Red border on invalid inputs
- Error summary at top of form if multiple errors
- Use `ff-form-error` CSS class

### Security Considerations

1. **CSRF Protection**: All forms include `authenticity_token`
2. **Authorization**: All actions verify `current_user` ownership
3. **Parameter Filtering**: Strong parameters in controller
4. **URL Validation**: Validate HTTP/HTTPS only, prevent SSRF
5. **Token Ownership**: Verify access token belongs to current_user
6. **Race Conditions**: Transaction wrapper for create with state=enabled

### Race Condition Protection Strategy

**During Create**:
```ruby
ActiveRecord::Base.transaction do
  @feed.save!

  if @feed.enabled?
    # Create initial schedule
    @feed.create_feed_schedule!
  end
end
```

**During Update**:
- No locking needed (last-write-wins acceptable)
- State changes remain separate (via FeedStatusesController, not edit form)

**Background Job Interference**:
- Background jobs use their own locking mechanisms (advisory locks in FeedRefreshJob)
- State changes are atomic via enum transitions
- Edit form doesn't change state, so minimal conflict risk



## UI/UX Guidelines

### Tone and Voice
Per CLAUDE.md requirements:
- Friendly but not overly casual
- Clear and brief
- Avoid technical jargon in labels/help text
- Don't expose implementation details (no "wizard", "modal", "form" in user-facing text)

**Examples**:
- ✅ "Check for new posts every" (not "Refresh interval")
- ✅ "Target Group" (not "FreeFeed group identifier")
- ✅ "Feed Type: RSS Feed" (not "Feed Profile: rss")
- ✅ "We couldn't identify a feed profile" (not "Profile identification failed")

### Form Layout
- Follow existing form patterns from AccessToken creation
- Use `ff-form-*` CSS classes for consistency
- Responsive: single column on mobile, optimized spacing on desktop
- Clear visual separation between sections

### Button States and Form Element Disabling

**Feed Identification Flow**:

**Identify Button** (_form_collapsed.html.erb):
- Disabled on form submit to prevent double-clicks
- Implemented via Stimulus controller listening to `turbo:submit-start` event
- Re-enabled only if validation error occurs and form re-renders
- During polling: Button is replaced by loading state (not visible)

**URL Input**:
- Disabled on form submit (same Stimulus controller as Identify button)
- Prevents editing mid-process

**Create/Update Flow**:

**Submit Button** (Create Feed / Update Feed):
- Disabled on form submit to prevent double-submission
- Standard Turbo behavior handles this automatically
- Label updates dynamically based on enable checkbox (feed-form Stimulus controller)
- Re-enabled if validation errors cause form re-render

**Access Token Selector**:
- Disabled while groups are being fetched for selected token
- Prevents race condition from rapid token changes
- Managed by groups-loader Stimulus controller
- Re-enabled after groups load (success or error)

**Target Group Selector**:
- Initially disabled until token is selected
- Disabled during groups loading (shows "Loading groups..." placeholder)
- Enabled after groups successfully loaded
- Never stuck in disabled state: loading always completes (success or error fallback)

**General Principle**: All disabled states are temporary and guaranteed to resolve via:
- Turbo Stream response (re-renders with enabled state)
- Stimulus controller managing disable/enable lifecycle
- Error handlers that re-enable controls even on failure



## Testing Requirements

### Model Tests
- `Feed#schedule_interval` and `#schedule_interval=` conversions
- `Feed.schedule_intervals_for_select` returns correct format
- Validation of schedule interval values
- **Uniqueness validation**: Rejects duplicate (user_id, url, target_group)
- **Uniqueness validation**: Allows same URL to different groups
- **Access token ownership**: Rejects token belonging to different user
- **Access token ownership**: Accepts token belonging to same user
- **Schedule interval validation**: Rejects invalid interval keys
- **Data consistency**: Transaction rolls back if schedule creation fails on enabled feed

### Controller Tests
- `FeedsController#new`:
  - Renders form when user has active tokens
  - Shows blocked state when user has no active tokens
  - Sets @has_active_tokens correctly
- `FeedsController#create`:
  - Success with valid params
  - Failure with invalid params
  - Creates enabled feed when checkbox checked and valid
  - Creates disabled feed when checkbox unchecked
  - Shows validation error if enable checked but can't enable
- `FeedsController#edit`: renders edit form
- `FeedsController#update`:
  - Success with valid params
  - Failure with invalid params
- `FeedDetailsController#create`:
  - Creates cache entry and enqueues job for valid URL
  - Reuses existing cache entry if present
  - Returns error for invalid URL
  - Returns loading state Turbo Stream
  - **Rate limiting**: Returns 429 when user exceeds 10 requests per hour
  - **Cache entry**: Includes `started_at` timestamp for timeout detection
- `FeedDetailsController#show`:
  - Returns processing state when status is "processing" and under 90s
  - **Timeout detection**: Returns error when processing exceeds 90 seconds
  - **Timeout cleanup**: Deletes stuck cache entry on timeout
  - Returns expanded form when status is "success"
  - Returns error when status is "failed"
  - Returns error when cache entry missing/expired
- `AccessTokensController#groups`:
  - Returns Turbo Stream with groups for active token owned by user
  - Renders target_group_selector partial with fetched groups
  - Renders empty selector for non-existent token
  - Renders empty selector for token owned by different user
  - Renders empty selector with error state when token inactive
  - Handles FreeFeed API errors gracefully (renders empty selector with help text)
  - **Cache failure handling**: Caches empty result for 1 minute on API error
  - **Race condition protection**: Uses `race_condition_ttl: 5.seconds`

### Job Tests
- `FeedIdentificationJob`:
  - Successfully identifies RSS feed and updates cache
  - Successfully identifies XKCD feed and updates cache
  - Extracts title correctly
  - Handles title extraction failure gracefully
  - Updates cache with failed status when profile not identified
  - Updates cache with failed status on HTTP errors
  - Uses correct cache key format
  - **No automatic retry**: Job does not retry on failure (user must retry manually)
  - **HTTP timeout**: Respects HttpClient timeout configuration (5s connect, 10s read)

### Integration Tests
- Complete flow: new form → identify (async) → poll → fill fields → create → show page
- Blocked state flow: user with no tokens visits new → sees blocked message → clicks add token link
- Edit flow: edit form → update → show page
- Identification failure flow: identify fails → retry with different URL
- Identification reuse flow: same URL identified twice within TTL → reuses cache
- Token change flow: select token → groups load → select group

### System Tests (if applicable)
- Turbo Stream interactions: token selection triggers Turbo Stream request and group selector updates
- Form state transitions: collapsed → loading → expanded
- Submit button label updates based on checkbox
- Polling behavior: identification polling stops on success/failure/timeout
- Button disabling: Identify button disabled on submit, prevents double-clicks
- Groups loading: Token selector disabled while groups loading, prevents race conditions
- Loading states: Groups selector shows "Loading groups..." while fetching
- Error recovery: All disabled states resolve (never stuck disabled)

### Test Data Setup
- Use FactoryBot for feed creation
- Mock HTTP responses for feed identification
- Mock FreeFeed API responses for groups endpoint
- Mock Rails.cache for feed identification tests
- Use `perform_enqueued_jobs` for testing async identification flow

### Test Coverage Goal
- Maintain 100% coverage for new code
- Use SimpleCov to verify



## Implementation Plan (High-Level)

This will be broken into separate PRs after spec approval:

### PR 1: Feed Model Schedule Intervals
1. Add schedule interval methods to Feed model
2. Model tests for schedule interval conversion methods

### PR 2: Profile Identification Infrastructure
1. Create FeedDetailsController with create and show actions
2. Create FeedIdentificationJob
3. Create identification partials (loading, error)
4. Controller and job tests
5. Mock HTTP responses and cache in tests

### PR 3: Groups API Endpoint
1. Add groups action to AccessTokensController
2. Add route
3. Implement FreefeedClient method to fetch groups
4. Controller tests with mocked API
5. Cache implementation

### PR 4: Feed Creation Flow
1. Update new action with active token check
2. Create blocked state partial (no active tokens)
3. Create collapsed form partial
4. Create expanded form partial
5. Implement create action
6. Form submission tests
7. Integration test for full flow including blocked state

### PR 5: Feed Editing Flow
1. Update edit action
2. Reuse/adapt form partial for edit mode
3. Implement update action
4. Update controller tests
5. Integration test for edit flow

### PR 6: Stimulus Controllers for Form Dynamics
1. Create feed-identification-controller (disable Identify button on submit)
2. Create groups-loader-controller (manage token/groups loading states)
3. Create feed-form-controller (submit button label updates)
4. Add data attributes to form elements
5. Configure polling_controller usage in identification_loading partial
6. Test all controllers with appropriate system/integration tests

### PR 7: Polish and Edge Cases
1. Empty states (no tokens, no groups)
2. Error message improvements
3. Loading states and indicators
4. Accessibility improvements (ARIA labels, keyboard navigation)



## Requirements and Assumptions

### Firm Requirements

1. **HTTP Client Timeout**: `HttpClient` **must** enforce timeouts to prevent indefinite hangs:
   - Connection timeout: **5 seconds**
   - Read timeout: **10 seconds**
   - Total timeout: **15 seconds maximum**
   - Max redirects: **5** (prevent redirect loops)
   - These are critical to prevent worker exhaustion from unresponsive URLs

2. **Job Failure Handling**: `FeedIdentificationJob` **must not** automatically retry on failure:
   - All failures update cache with `status: "failed"` and error message
   - User sees error in UI and decides whether to retry manually
   - No exponential backoff or automatic retry logic
   - Transient network errors require user to re-submit

3. **Rate Limiting**: Feed identification endpoint **must** enforce rate limits:
   - **10 requests per hour per user**
   - Prevents job queue flooding
   - Returns 429 Too Many Requests with clear error message

4. **Stuck Job Detection**: Server **must** detect and recover from stuck "processing" state:
   - Timeout threshold: **90 seconds** from `started_at` timestamp
   - Automatically clean up stuck cache entries
   - Show timeout error to user with retry option

### Assumptions

1. **Group Validation**: Validating format only, not existence in FreeFeed. If group doesn't exist, posting will fail gracefully during background job. This is acceptable.

2. **Title Extraction Failure**: If title extractor returns nil/empty, the name field will be blank and user must fill it manually. This is expected behavior.

3. **Custom Cron Expressions**: Not supported in initial implementation. Users must choose from predefined intervals. Could be future enhancement.

4. **SSRF Protection**: URL validation prevents obvious internal network access (localhost, 127.0.0.1, etc.). Additional safeguards may be needed depending on deployment environment.



## Success Criteria

- ✅ User can create a new feed by entering URL and identifying profile
- ✅ User can configure all feed settings (title, token, group, schedule, state)
- ✅ User can edit existing feed configuration (except URL and profile)
- ✅ Profile identification works for RSS and XKCD feeds
- ✅ Groups are fetched dynamically based on selected token
- ✅ Form validates all fields and shows helpful error messages
- ✅ Feed can be created in enabled or disabled state
- ✅ Concurrent edits are handled gracefully with clear messaging
- ✅ All code follows atomic commit guidelines from CLAUDE.md
- ✅ Test coverage is 100% for new code
- ✅ RuboCop passes for all Ruby files
- ✅ UI text follows tone guidelines from CLAUDE.md



This specification is ready for your review. Please confirm if this aligns with your vision, or let me know if any adjustments are needed.
