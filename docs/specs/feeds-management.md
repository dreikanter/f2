# Feed CRUD Requirements Specification

## Overview

Implement create, edit, and delete functionality for Feed records in the Feeder application. This feature allows users to configure feed sources, detect feed profiles, and set up automated content reposting to FreeFeed groups.

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

- [ ] Feed creation flow with profile identification
- [ ] Feed editing form
- [ ] `FeedsController#create` and `#update` actions
- [ ] Profile identification endpoint
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
- **Detect Button**: Primary action button
  - Label: "Detect Feed Format"
  - Triggers profile identification

#### 1.3 Initiate Profile Detection Process

**Endpoint**: `POST /feeds/details` (`create` action starts identification process)

**Request Parameters**:
- `url`: The feed URL to detect

**Server-side Process**:
1. Create a temporary DB record `FeedDetails` (`url: url, status: processing`) (avoid creating duplicates; if the record already exists, do not run the background job)
2. Run a background job that will identify and persist feed details in a temporary DB record (`FeedDetails`)
3. Return Turbo Stream response, switching the page to "Loading" state (see `FeedPreviewsController` for an example)

**Background Job**:
1. Accept `FeedDetails` record from parameters and validate it's URL format (HTTP/HTTPS)
2. Fetch feed data from the HTTP URL
3. Run `FeedProfileDetector.detect(url, response)`
4. If profile matched:
   - Run appropriate `TitleExtractor` for the profile
   - Extract feed title
5. Save details to the `FeedDetails` and update it's status to `success` or `failed`, depending on identification result

#### 1.4 Poll for the Profile Detection Result

**Endpoint**: `GET /feeds/details` (`show` action responds to polling for the identification results)

**Request Parameters**:
- `url`: The feed URL that is now a key to find the identification result

**Server-side Process**:
1. Find the `FeedDetails` record matching the provided URL parameter
2. Return Turbo Stream response

**Success Response** (Turbo Stream):
- Replace form with expanded version including:
  - Detected profile
  - Extracted title (or empty if extraction failed)
  - All configuration fields

**Failure Response** (Turbo Stream):
- Show inline error message in form
- Keep URL field populated for editing
- Error message: "We couldn't detect a feed profile for this URL. Please check the URL and try again, or try a different feed source."
- Do not create any database records

**No Manual Profile Override**: If detection fails, users must try a different URL. No dropdown to manually select profiles.

#### 1.5 Expanded Form State

After successful detection, show:

**1. URL (Read-only)**
- Display as disabled text input (grayed out)
- Value remains submitted but not editable
- Label: "Feed URL"

**2. Detected Profile (Read-only)**
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

#### 1.6 No Data Persistence During Detection

**Critical**: Profile detection does NOT create database records. All detected/extracted data (URL, profile, title) are form parameters that get submitted when the user clicks the final create button.



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
  collection do
    post :detect # Profile detection endpoint
  end
  resource :status, only: :update, controller: "feed_statuses"
  resource :purge, only: :create, controller: "feeds/purges"
end

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

#### FeedsController#detect (NEW)

```ruby
def detect
  url = params[:url]

  # Validate URL format
  unless url.present? && url.match?(URI::DEFAULT_PARSER.make_regexp(%w[http https]))
    return render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/detection_error",
      locals: { url: url, error: "Please enter a valid URL" }
    )
  end

  # Fetch and detect profile
  response = Loader::HttpLoader.new(url).load
  profile_key = FeedProfileDetector.detect(url, response)

  if profile_key
    # Extract title
    title_extractor = FeedProfile.title_extractor_class_for(profile_key).new(url, response)
    title = title_extractor.title rescue nil

    @feed = current_user.feeds.build(
      url: url,
      feed_profile_key: profile_key,
      name: title
    )

    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/form_expanded",
      locals: { feed: @feed, profile_key: profile_key }
    )
  else
    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/detection_error",
      locals: { url: url, error: "We couldn't detect a feed profile for this URL." }
    )
  end
rescue => e
  render turbo_stream: turbo_stream.replace(
    "feed-form",
    partial: "feeds/detection_error",
    locals: { url: url, error: "An error occurred while checking this feed." }
  )
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
- Initial detection form
- URL input + Detect button

**app/views/feeds/_form_expanded.html.erb**:
- Full form with all fields
- Used after detection succeeds and for edit mode
- Handles read-only URL/profile for edit

**app/views/feeds/_detection_error.html.erb**:
- Error state after failed detection
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
- ✅ "We couldn't detect a feed profile" (not "Profile detection failed")

### Form Layout
- Follow existing form patterns from AccessToken creation
- Use `ff-form-*` CSS classes for consistency
- Responsive: single column on mobile, optimized spacing on desktop
- Clear visual separation between sections

### Button States
- Disable submit button during form processing
- Show loading indicator on Detect button during detection
- Disable group selector until token is selected



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
- `FeedsController#detect`:
  - Success with valid RSS feed
  - Failure with invalid URL
  - Failure with non-feed URL
  - Extracts title correctly
- `AccessTokensController#groups`:
  - Returns groups for active token owned by user
  - Returns 404 for non-existent token
  - Returns 404 for token owned by different user
  - Returns 422 for inactive token
  - Handles FreeFeed API errors gracefully

### Integration Tests
- Complete flow: new form → detect → fill fields → create → show page
- Edit flow: edit form → update → show page
- Detection failure flow: detect fails → retry with different URL
- Token change flow: select token → groups load → select group
- Concurrent edit flow: two users edit same feed → second sees error

### System Tests (if applicable)
- JavaScript interactions: token selection triggers group load
- Form state transitions: collapsed → expanded
- Submit button label updates based on checkbox

### Test Data Setup
- Use FactoryBot for feed creation
- Mock HTTP responses for feed detection
- Mock FreeFeed API responses for groups endpoint

### Test Coverage Goal
- Maintain 100% coverage for new code
- Use SimpleCov to verify



## Implementation Plan (High-Level)

This will be broken into separate PRs after spec approval:

### PR 1: Model and Database Foundation
1. Add lock_version column migration
2. Add schedule interval methods to Feed model
3. Model tests for new methods

### PR 2: Profile Detection Infrastructure
1. Add detect action to FeedsController
2. Create detection error partial
3. Controller tests for detection
4. Mock HTTP responses in tests

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

5. **Profile Detection Timeout**: Need to define timeout for HTTP requests during detection (suggest 10 seconds) to prevent hanging.

6. **SSRF Protection**: URL validation should prevent internal network access. May need additional safeguards depending on deployment environment.



## Success Criteria

- ✅ User can create a new feed by entering URL and detecting profile
- ✅ User can configure all feed settings (title, token, group, schedule, state)
- ✅ User can edit existing feed configuration (except URL and profile)
- ✅ Profile detection works for RSS and XKCD feeds
- ✅ Groups are fetched dynamically based on selected token
- ✅ Form validates all fields and shows helpful error messages
- ✅ Feed can be created in enabled or disabled state
- ✅ Concurrent edits are handled gracefully with clear messaging
- ✅ All code follows atomic commit guidelines from CLAUDE.md
- ✅ Test coverage is 100% for new code
- ✅ RuboCop passes for all Ruby files
- ✅ UI text follows tone guidelines from CLAUDE.md



This specification is ready for your review. Please confirm if this aligns with your vision, or let me know if any adjustments are needed.
