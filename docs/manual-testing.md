# Manual Testing Guide - Feed Creation Flow

This guide provides step-by-step testing instructions for the feed creation feature, including the recent validation error handling improvements.

## Prerequisites

### 1. Setup Development Environment

```bash
# Start PostgreSQL
su - postgres -c "/usr/lib/postgresql/16/bin/pg_ctl start -D /var/lib/postgresql/16/main -l /tmp/postgres.log -o '-c config_file=/etc/postgresql/16/main/postgresql.conf'"

# Create development database (if needed)
HOST=localhost:3000 bin/rails db:create db:migrate

# Start Rails server
HOST=localhost:3000 bin/rails server
```

### 2. Create Test Data

```bash
# Load seed data (creates test user, access tokens, sample feeds)
HOST=localhost:3000 bin/rails db:seed
```

This creates:
- **User**: test@example.com / password123 (active state, admin permissions)
- **Access Tokens**: 3 active tokens and 2 inactive tokens for freefeed.net
- **Sample Feeds**: 5 example feeds (4 enabled, 1 disabled) with posts and events

### 3. Sign In

1. Navigate to `http://localhost:3000`
2. Sign in with:
   - Email: `test@example.com`
   - Password: `password123`

---

## Test Scenarios

### Test 1: Blocked State (No Active Tokens)

**Setup:**
```ruby
# In Rails console: HOST=localhost:3000 bin/rails console
token = AccessToken.first
token.update!(status: :inactive)
```

**Steps:**
1. Navigate to `/feeds/new`

**Expected:**
- ✅ Warning alert with amber background (`ff-alert ff-alert--warning`)
- ✅ Message: "You need to have an active FreeFeed access token before creating a feed."
- ✅ Two buttons: "Add Access Token" and "Cancel"
- ✅ No card border around content
- ✅ Clean, minimal layout

**Re-enable token:**
```ruby
token.update!(status: :active)
```

---

### Test 2: Happy Path - Create Enabled Feed

**Steps:**
1. Navigate to `/feeds/new`
2. Enter URL: `https://xkcd.com/rss.xml`
3. Click "Identify Feed Format"
4. Wait for form to expand (~1-2 seconds)

**Verify expanded form:**
- ✅ Feed URL field (disabled, grayed out)
- ✅ Feed Type: "RSS/Atom Feed" (disabled)
- ✅ Feed Name: Auto-populated
- ✅ FreeFeed Account: Shows "Test Token"
- ✅ Target Group: Select dropdown (initially disabled)
- ✅ Schedule: "1 hour" (default)
- ✅ "Enable feed" checkbox: Checked by default

**Continue:**
5. Enter Target Group: `testgroup` (lowercase)
6. Click "Create and Enable Feed"

**Expected Results:**
- ✅ Redirects to `/feeds/[id]`
- ✅ Green success message: "Feed 'xkcd.com' was successfully created and is now active. New posts will be checked every 1 hour and published to testgroup."
- ✅ Feed details page displays

**Verify in console:**
```ruby
feed = Feed.last
feed.name                           # => "xkcd.com"
feed.url                            # => "https://xkcd.com/rss.xml"
feed.enabled?                       # => true
feed.feed_schedule.present?         # => true
feed.feed_schedule.next_run_at      # => Recent timestamp (not nil!)
feed.feed_schedule.last_run_at      # => Recent timestamp (not nil!)
Feed.due.include?(feed)             # => true (critical!)
```

---

### Test 3: Create Disabled Feed

**Steps:**
1. Navigate to `/feeds/new`
2. Enter URL: `https://example.com/feed.xml`
3. Click "Identify Feed Format"
4. Change Feed Name to: "My Disabled Feed"
5. **Uncheck** "Enable feed" checkbox
6. **Watch button text change** to "Create Feed"
7. Enter Target Group: `testgroup`
8. Click "Create Feed"

**Expected Results:**
- ✅ Redirects to feed show page
- ✅ Message: "Feed 'My Disabled Feed' was successfully created but is currently disabled..."
- ✅ No feed schedule created

**Verify in console:**
```ruby
feed = Feed.last
feed.name                     # => "My Disabled Feed"
feed.disabled?                # => true
feed.feed_schedule.present?   # => false
```

---

### Test 4: 🆕 Validation Error - Missing Target Group

**This tests the NEW fix for preserving user input on validation errors.**

**Steps:**
1. Navigate to `/feeds/new`
2. Enter URL: `https://example.com/another-feed.xml`
3. Click "Identify Feed Format"
4. Wait for expanded form
5. Change Feed Name to: "Test Validation"
6. Change Schedule to: "2 hours"
7. **Do NOT enter a Target Group** (leave blank/placeholder)
8. Ensure "Enable feed" is checked
9. Click "Create and Enable Feed"

**Expected Results (THE CRITICAL FIX):**
- ✅ Page re-renders with HTTP 422 status
- ✅ **EXPANDED form is still shown** (NOT collapsed URL form!)
- ✅ All inputs are preserved:
  - URL: "https://example.com/another-feed.xml" (disabled field)
  - Feed Name: "Test Validation"
  - Schedule: "2 hours"
  - "Enable feed" checkbox: Still checked
- ✅ Red error message below Target Group: "can't be blank"
- ✅ Error uses `ff-form-error` class

**What you should NOT see:**
- ❌ Blank collapsed form with just URL input
- ❌ Lost feed name or schedule
- ❌ Need to re-identify the feed
- ❌ Starting over from step 1

**Fix and retry:**
10. Enter Target Group: `testgroup`
11. Click "Create and Enable Feed" again
12. Should successfully create the feed

---

### Test 5: Validation Error - Missing Name

**Steps:**
1. Navigate to `/feeds/new`
2. Enter URL: `https://example.com/test.xml`
3. Click "Identify Feed Format"
4. **Clear the Feed Name field** completely
5. Enter Target Group: `testgroup`
6. Click "Create and Enable Feed"

**Expected Results:**
- ✅ Expanded form re-renders with errors
- ✅ Error below Feed Name: "can't be blank"
- ✅ Help text changes to: "We couldn't automatically detect a name. Please enter one."
- ✅ Target group value "testgroup" is preserved
- ✅ All other inputs preserved

---

### Test 6: Button Label Toggle (Stimulus)

**Tests:** Dynamic button label switching via JavaScript

**Steps:**
1. Navigate to `/feeds/new`
2. Enter any valid URL and identify feed
3. In expanded form, toggle "Enable feed" checkbox multiple times
4. Watch the submit button text

**Expected:**
- ✅ Checked → "Create and Enable Feed"
- ✅ Unchecked → "Create Feed"
- ✅ Smooth, instant switching

---

### Test 7: Visual Consistency

**Compare these pages:**
- `/feeds/new` (after identifying a feed)
- `/access_tokens/new`

**Verify:**
- ✅ NO card borders on forms
- ✅ All use `ff-card__footer` for button sections
- ✅ Buttons are full-width (not compact)
- ✅ Consistent spacing and field styling
- ✅ Alert boxes use standard `ff-alert` classes

---

### Test 8: Select vs Input Height

**Steps:**
1. Navigate to expanded feed form
2. Open browser DevTools (F12)
3. Inspect these elements:
   - "Feed Name" text input
   - "FreeFeed Account" select dropdown
   - "Check for new posts every" select dropdown

**Check in DevTools:**
- ✅ All have class `ff-form-input`
- ✅ All have class `leading-normal`
- ✅ Computed height is identical (~44px)
- ✅ No visible height differences

---

### Test 9: Schedule Timestamps (Critical Bug Fix)

**After creating an enabled feed:**

```ruby
feed = Feed.last
schedule = feed.feed_schedule

# These must NOT be nil!
schedule.next_run_at    # => 2024-01-15 10:30:00 UTC (example)
schedule.last_run_at    # => 2024-01-15 10:30:00 UTC (example)

# Feed MUST appear in the due queue
Feed.due.where(id: feed.id).exists?  # => true

# Verify the scope query
Feed.due.to_sql
# Should include: feed_schedules.next_run_at <= [current time]
```

**Why this matters:**
- If `next_run_at` is NULL, feed won't be processed by `FeedSchedulerJob`
- This was a critical bug that prevented new feeds from refreshing

---

## Cleanup

```ruby
# In Rails console
User.first.feeds.destroy_all      # Remove all test feeds
User.first.destroy                # Remove test user completely

# Or check what exists
User.pluck(:id, :email_address, :state)
AccessToken.pluck(:id, :name, :host, :status)
Feed.pluck(:id, :name, :state, :url)
```

---

## Success Criteria Checklist

- [ ] Validation errors preserve all user input
- [ ] Expanded form re-renders on validation failure (not collapsed form)
- [ ] Feed schedules have `next_run_at` and `last_run_at` populated
- [ ] Enabled feeds appear in `Feed.due` scope
- [ ] No card borders on feed forms
- [ ] Select and input fields have identical height
- [ ] Alert boxes use standard `ff-alert` classes
- [ ] Button labels toggle dynamically with checkbox

---

## Troubleshooting

**PostgreSQL not running:**
```bash
su - postgres -c "/usr/lib/postgresql/16/bin/pg_ctl start -D /var/lib/postgresql/16/main -l /tmp/postgres.log -o '-c config_file=/etc/postgresql/16/main/postgresql.conf'"
```

**Database doesn't exist:**
```bash
HOST=localhost:3000 bin/rails db:create db:migrate
```

**Need fresh test data:**
```bash
# Reset database and reload seed data
HOST=localhost:3000 bin/rails db:reset
# Or just reload seeds without dropping database
HOST=localhost:3000 bin/rails db:seed
```

**Rails console:**
```bash
HOST=localhost:3000 bin/rails console
```
