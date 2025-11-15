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

**Server-side Process**:
1. Generate cache key from `current_user.id` and URL
2. Fetch data from Rails cache
3. Based on status, return appropriate Turbo Stream response

**Success Response** (Turbo Stream, when `status: "success"`):
- Replace form with expanded version including:
  - Identified profile
  - Extracted title (or empty if extraction failed)
  - All configuration fields

**Processing Response** (Turbo Stream, when `status: "processing"`):
- Keep polling state active
- Show loading indicator

**Failure Response** (Turbo Stream, when `status: "failed"`):
- Show inline error message in form
- Keep URL field populated for editing
- Error message: "We couldn't identify a feed profile for this URL. Please check the URL and try again, or try a different feed source."

**No Manual Profile Override**: If identification fails, users must try a different URL. No dropdown to manually select profiles.

#### 1.5 Expanded Form State

After successful identification, show:

**1. URL (Read-only)**
- Display as disabled text input (grayed out, see current email field at `app/views/settings/email_updates/edit.html.erb` for example)
- Value remains submitted but not editable
- Label: "Feed URL"

**2. Identified Profile (Read-only)**
- Display as static text field styled like form input
- Show profile name in human-readable format (e.g., "RSS Feed")
- Label: "Feed Type"
- Hidden input submits `feed_profile_key`

**3. Feed Title (Editable)**
- Text input pre-filled with extracted title
- User can modify
- Label: "Feed Name"
- Validation: Required, max 40 chars, unique within user's scope
- Help text: "This name will be displayed in your feeds list"

**4. Reposting Configuration Section**
Section header: "Reposting Settings"

**4.1 Access Token Selector**
- Dropdown select
- Label: "FreeFeed Account"
- Shows only active tokens for current user
- Display format: `{host_domain} - {owner}` (e.g., "freefeed.net - username")
- Uses `AccessToken.active.where(user: current_user)`
- Required field
- Empty state message (if no active tokens): "You need to add an active access token first. [Add Token]" (link to settings)

**4.2 Target Group Selector**
- Dropdown select (initially disabled/empty)
- Label: "Target Group"
- Dynamically populated when access token is selected
- Fetches from: `GET /access_tokens/:id/groups` (returns JSON)
- Display format: Group name as shown in FreeFeed API
- Required field
- Allows manual text entry as fallback
- Validation: Lowercase letters, numbers, underscores, dashes only; max 80 chars
- Help text: "The FreeFeed group where posts will be published"

**4.3 Groups Endpoint Implementation**
`GET /access_tokens/:id/groups`

**Logic**:
1. Verify access token belongs to `current_user` (401 if not)
2. Verify token is active (422 if not)
3. Fetch groups via `FreefeedClient` (built from token)
4. Cache result for 10 minutes (keyed by token_id)
5. Return JSON array of group names

**Response Format**:
```json
{
  "groups": ["group1", "group2", "group3"]
}
```

**Error Handling**:
- 401: Unauthorized (token doesn't belong to user)
- 422: Token not active or FreeFeed API error
- Return empty array on API failure (allow manual entry)

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

#### 2.4 Concurrent Edit Protection

Use **optimistic locking** to handle concurrent modifications:

**Implementation**:
1. Add `lock_version` column to feeds table (integer, default 0)
2. Include `lock_version` as hidden field in edit form
3. On update, Rails automatically checks version match
4. On `StaleObjectError`:
   - Show friendly error message: "This feed was modified by another user or process. Please review the current settings and try again."
   - Redirect back to edit form with current (reloaded) data

**Edge Case - Background Disabling**:
If background job disables feed while user is editing:
- Optimistic lock will catch this
- User sees current state (disabled) when redirected to edit form
- Form validation allows saving even if disabled (state is not in edit form)



### 3. Feed Deletion

**Current Implementation**: Already exists via `DELETE /feeds/:id`
- Triggered from show page "Delete Feed" button in danger zone
- Confirmation modal required
- Cascading deletes: feed_schedule, events, feed_entries, feed_metrics, posts

**No changes required** to deletion flow.



## Technical Implementation Details

### Database Changes

**Migration 1: Add lock_version to feeds**
```ruby
add_column :feeds, :lock_version, :integer, default: 0, null: false
```

### Routing Changes

Add to `config/routes.rb`:
```ruby
resources :feeds do
  resource :status, only: :update, controller: "feed_statuses"
  resource :purge, only: :create, controller: "feeds/purges"
end

resource :feed_details, only: [:create, :show], path: 'feeds/details'

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
```

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
rescue ActiveRecord::StaleObjectError
  flash.now[:error] = "This feed was modified by another user or process. Please review the current settings and try again."
  @feed.reload
  render :edit, status: :conflict
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
      { status: "processing", url: url },
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
rescue => e
  Rails.logger.error("Feed identification initiation failed: #{e.message}")
  render turbo_stream: turbo_stream.replace(
    "feed-form",
    partial: "feeds/identification_error",
    locals: { url: url, error: "An error occurred while checking this feed." }
  )
end

private

def feed_identification_cache_key(url)
  "feed_identification/#{current_user.id}/#{Digest::SHA256.hexdigest(url)}"
end
```

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
    # Still processing, keep polling
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
rescue => e
  Rails.logger.error("Feed identification polling failed: #{e.message}")
  render turbo_stream: turbo_stream.replace(
    "feed-form",
    partial: "feeds/identification_error",
    locals: { url: url, error: "An error occurred while checking identification status." }
  )
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
    @token = current_user.access_tokens.find(params[:id])

    unless @token.active?
      return render json: { error: "Token is not active" }, status: :unprocessable_entity
    end

    groups = Rails.cache.fetch("access_token_groups/#{@token.id}", expires_in: 10.minutes) do
      fetch_groups_from_freefeed(@token)
    end

    render json: { groups: groups }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Access token not found" }, status: :not_found
  rescue => e
    Rails.logger.error("Failed to fetch groups for token #{@token.id}: #{e.message}")
    render json: { groups: [] } # Allow manual entry on error
  end

  private

  def fetch_groups_from_freefeed(token)
    client = token.build_client
    # Assuming FreefeedClient has a method to fetch groups
    # This will need to be implemented based on FreeFeed API
    client.fetch_managed_groups.map(&:username) # Returns array of group names
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
      response = Loader::HttpLoader.new(url).load

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

### Stimulus Controllers

#### feed-form-controller.js

Handles:
- Form state management (collapsed vs expanded)
- Dynamic group loading when token changes
- Form validation feedback
- Enable checkbox state tracking

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["groupSelect", "tokenSelect", "enableCheckbox", "submitButton"]

  connect() {
    this.updateSubmitButtonLabel()
  }

  async tokenChanged(event) {
    const tokenId = event.target.value

    if (!tokenId) {
      this.groupSelectTarget.innerHTML = '<option value="">Select a token first</option>'
      this.groupSelectTarget.disabled = true
      return
    }

    this.groupSelectTarget.disabled = true
    this.groupSelectTarget.innerHTML = '<option value="">Loading groups...</option>'

    try {
      const response = await fetch(`/access_tokens/${tokenId}/groups`)
      const data = await response.json()

      if (data.groups && data.groups.length > 0) {
        this.groupSelectTarget.innerHTML = '<option value="">Select a group</option>' +
          data.groups.map(g => `<option value="${g}">${g}</option>`).join('')
      } else {
        this.groupSelectTarget.innerHTML = '<option value="">No groups available (you can type manually)</option>'
      }

      this.groupSelectTarget.disabled = false
    } catch (error) {
      console.error('Failed to load groups:', error)
      this.groupSelectTarget.innerHTML = '<option value="">Error loading groups (you can type manually)</option>'
      this.groupSelectTarget.disabled = false
    }
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

**app/views/feeds/_identification_loading.html.erb**:
- Loading state during async identification
- Shows loading indicator
- Polls `GET /feeds/details` via Turbo Stream

**app/views/feeds/_identification_error.html.erb**:
- Error state after failed identification
- Shows error message and URL input for retry

### Form Field Considerations

**Access Token Selector**:
- If user has no active tokens: Show prominent message with link to `/settings/access_tokens/new`
- Empty state handled gracefully

**Target Group Selector**:
- Combo box: dropdown + manual text entry
- Uses `datalist` HTML5 element for suggestions while allowing free text
- JavaScript populates datalist from API response

**Schedule Interval Selector**:
- Standard select dropdown
- Human-readable labels, cron values hidden

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
6. **Race Conditions**:
   - Optimistic locking for updates
   - Transaction wrapper for create with state=enabled
   - Atomic operations where needed

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
- Use optimistic locking (lock_version)
- If concurrent modification: reload and show error
- State changes remain separate (via FeedStatusesController)

**Background Job Interference**:
- Background jobs use their own locking mechanisms (advisory locks in FeedRefreshJob)
- State changes are atomic via enum transitions
- Edit form doesn't change state, so no conflict



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

### Button States
- Disable submit button during form processing
- Show loading indicator during async identification (polling state)
- Disable group selector until token is selected
- Disable Identify button while identification is in progress



## Testing Requirements

### Model Tests
- `Feed#schedule_interval` and `#schedule_interval=` conversions
- `Feed.schedule_intervals_for_select` returns correct format
- Optimistic locking behavior on concurrent updates
- Validation of schedule interval values

### Controller Tests
- `FeedsController#new`: renders form
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
  - Handles stale object error
- `FeedDetailsController#create`:
  - Creates cache entry and enqueues job for valid URL
  - Reuses existing cache entry if present
  - Returns error for invalid URL
  - Returns loading state Turbo Stream
- `FeedDetailsController#show`:
  - Returns processing state when status is "processing"
  - Returns expanded form when status is "success"
  - Returns error when status is "failed"
  - Returns error when cache entry missing/expired
- `AccessTokensController#groups`:
  - Returns groups for active token owned by user
  - Returns 404 for non-existent token
  - Returns 404 for token owned by different user
  - Returns 422 for inactive token
  - Handles FreeFeed API errors gracefully

### Job Tests
- `FeedIdentificationJob`:
  - Successfully identifies RSS feed and updates cache
  - Successfully identifies XKCD feed and updates cache
  - Extracts title correctly
  - Handles title extraction failure gracefully
  - Updates cache with failed status when profile not identified
  - Updates cache with failed status on HTTP errors
  - Uses correct cache key format

### Integration Tests
- Complete flow: new form → identify (async) → poll → fill fields → create → show page
- Edit flow: edit form → update → show page
- Identification failure flow: identify fails → retry with different URL
- Identification reuse flow: same URL identified twice within TTL → reuses cache
- Token change flow: select token → groups load → select group
- Concurrent edit flow: two users edit same feed → second sees error

### System Tests (if applicable)
- JavaScript interactions: token selection triggers group load
- Form state transitions: collapsed → expanded
- Submit button label updates based on checkbox

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

### PR 1: Model and Database Foundation
1. Add lock_version column migration
2. Add schedule interval methods to Feed model
3. Model tests for new methods

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
1. Update new action
2. Create collapsed form partial
3. Create expanded form partial
4. Implement create action
5. Form submission tests
6. Integration test for full flow

### PR 5: Feed Editing Flow
1. Update edit action
2. Reuse/adapt form partial for edit mode
3. Implement update action with optimistic locking
4. Update controller tests
5. Integration test for edit flow

### PR 6: Stimulus Controller for Form Dynamics
1. Create feed-form Stimulus controller
2. Implement token change → group load
3. Implement submit button label updates
4. Add data attributes to form elements

### PR 7: Polish and Edge Cases
1. Empty states (no tokens, no groups)
2. Error message improvements
3. Loading states and indicators
4. Accessibility improvements (ARIA labels, keyboard navigation)



## Open Questions / Assumptions

1. **FreefeedClient#fetch_managed_groups**: Assuming this method exists or will be implemented. Need to verify FreeFeed API endpoint for fetching user's managed groups.

2. **Group Validation**: We're validating format only, not existence in FreeFeed. If group doesn't exist, posting will fail gracefully during background job. This is acceptable per specification.

3. **Title Extraction Failure**: If title extractor returns nil/empty, the name field will be blank and user must fill it manually. This is expected behavior.

4. **Custom Cron Expressions**: Not supported in initial implementation. Users must choose from predefined intervals. Could be future enhancement.

5. **Profile Identification Timeout**: HTTP requests during identification should timeout after 10 seconds to prevent hanging. This should be configured in `Loader::HttpLoader`.

6. **SSRF Protection**: URL validation should prevent internal network access. May need additional safeguards depending on deployment environment.



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
