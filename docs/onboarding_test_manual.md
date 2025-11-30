# Onboarding Flow Testing Manual

This manual provides test cases for validating the onboarding flow and status page states. Each test case includes setup scripts that can be run with Rails runner and detailed steps for browser agent testing.

## Prerequisites

- Development environment is set up
- Database is seeded: `bin/rails db:seed`
- Default user credentials: `test@example.com` / `password123`

## Test Cases

### Test Case 1: New User - Onboarding State 1 (No Active Tokens)

**Objective:** Verify that a user in onboarding state without active tokens sees the token setup prompt.

**Setup:**
```ruby
# Run in Rails console or as oneliner:
bin/rails runner "u = User.find_by(email_address: 'test@example.com'); u.update!(state: :onboarding); u.access_tokens.update_all(status: :inactive); puts 'Setup complete: User is onboarding, all tokens inactive'"
```

**Expected State:**
- User state: `onboarding`
- Active tokens: 0
- Feeds: 0 or more (doesn't matter)

**Test Steps:**
1. Navigate to the login page
2. Sign in with email `test@example.com` and password `password123`
3. You should be redirected to the Status page
4. Verify the page displays:
   - Heading: "Welcome to Feeder"
   - Text: "Feeder helps you automatically share content from your favorite sources to FreeFeed."
   - Text: "To get started, add a FreeFeed access token so Feeder can post on your behalf."
   - Button: "Add FreeFeed token"
5. Click the "Add FreeFeed token" button
6. Verify you are redirected to the token creation page

**Cleanup:**
```ruby
bin/rails runner "u = User.find_by(email_address: 'test@example.com'); u.update!(state: :active); puts 'Cleanup complete'"
```

---

### Test Case 2: New User - Onboarding State 2 (Has Token, No Feeds)

**Objective:** Verify that a user in onboarding state with an active token but no feeds sees the feed creation prompt.

**Setup:**
```ruby
# Run in Rails console or as oneliner:
bin/rails runner "u = User.find_by(email_address: 'test@example.com'); u.update!(state: :onboarding); u.feeds.destroy_all; u.access_tokens.each { |t| t.update!(status: :active) if t.status != 'active' }; puts 'Setup complete: User is onboarding, has active tokens, no feeds'"
```

**Expected State:**
- User state: `onboarding`
- Active tokens: 1 or more
- Feeds: 0

**Test Steps:**
1. Navigate to the login page
2. Sign in with email `test@example.com` and password `password123`
3. You should be redirected to the Status page
4. Verify the page displays:
   - Heading: "Welcome to Feeder"
   - Text: "Great! You've added a FreeFeed access token. Now you can create your first feed."
   - Button: "Add feed"
5. Click the "Add feed" button
6. Verify you are redirected to the feed creation page

**Cleanup:**
```bash
bin/rails runner "u = User.find_by(email_address: 'test@example.com'); u.update!(state: :active); puts 'User state reset'"
bin/rails db:seed
```

---

### Test Case 3: Completing Onboarding - State Transition

**Objective:** Verify that creating the first feed transitions the user from onboarding to active state.

**Setup:**
```ruby
# Run in Rails console or as oneliner:
bin/rails runner "u = User.find_by(email_address: 'test@example.com'); u.update!(state: :onboarding); u.feeds.destroy_all; u.access_tokens.first.update!(status: :active); puts 'Setup complete: User ready to complete onboarding'"
```

**Expected State:**
- User state: `onboarding`
- Active tokens: 1 or more
- Feeds: 0

**Test Steps:**
1. Sign in with email `test@example.com` and password `password123`
2. You should see the "Welcome to Feeder" page with "Add feed" button
3. Click "Add feed"
4. Fill in the feed creation form:
   - URL: `https://feeds.feedburner.com/GoogleOpenSourceBlog`
   - Click "Identify Feed" (wait for it to load)
   - Name: "Test Feed"
   - Target Group: "test-group"
   - Schedule: Select "Every hour"
   - Check "Enable feed immediately"
5. Click "Create Feed"
6. Verify you are redirected to the feed details page
7. Navigate back to the Status page (click "Status" in navigation)
8. Verify the page NOW displays:
   - Heading: "Status" (NOT "Welcome to Feeder")
   - User statistics section
   - No warning alerts

**Cleanup:**
```bash
bin/rails runner "Feed.find_by(name: 'Test Feed')&.destroy; puts 'Feed removed'"
bin/rails db:seed
```

---

### Test Case 4: Active User - Normal Dashboard (State 3)

**Objective:** Verify that an active user with active tokens and feeds sees the normal dashboard.

**Setup:**
```ruby
# Run in Rails console or as oneliner:
bin/rails runner "u = User.find_by(email_address: 'test@example.com'); u.update!(state: :active); u.access_tokens.first.update!(status: :active) unless u.access_tokens.active.any?; puts 'Setup complete: Active user with active tokens and feeds'"
```

**Expected State:**
- User state: `active`
- Active tokens: 1 or more
- Feeds: 1 or more

**Test Steps:**
1. Sign in with email `test@example.com` and password `password123`
2. You should be redirected to the Status page
3. Verify the page displays:
   - Heading: "Status"
   - User statistics including:
     - Total Feeds
     - Total Imported Posts
     - Total Published Posts
     - Recent Activity section (if there are events)
   - NO "Welcome to Feeder" message
   - NO warning alerts about missing tokens

**Cleanup:**
```ruby
# No cleanup needed - this is the default state
```

---

### Test Case 5: Active User - Missing Active Tokens (State 4)

**Objective:** Verify that an active user with no active tokens sees a warning but still displays the dashboard.

**Setup:**
```ruby
# Run in Rails console or as oneliner:
bin/rails runner "u = User.find_by(email_address: 'test@example.com'); u.update!(state: :active); u.access_tokens.update_all(status: :inactive); puts 'Setup complete: Active user with all tokens inactive'"
```

**Expected State:**
- User state: `active`
- Active tokens: 0
- Feeds: 1 or more

**Test Steps:**
1. Sign in with email `test@example.com` and password `password123`
2. You should be redirected to the Status page
3. Verify the page displays:
   - Heading: "Status"
   - Warning alert (yellow/orange box) containing:
     - Text: "You don't have any active FreeFeed tokens."
     - Link: "Add a token" (links to new token page)
   - User statistics section BELOW the warning
   - Recent Activity section (if there are events)
   - NO "Welcome to Feeder" message
4. Click the "Add a token" link in the warning
5. Verify you are redirected to the token creation page

**Cleanup:**
```ruby
bin/rails runner "u = User.find_by(email_address: 'test@example.com'); u.access_tokens.first.update!(status: :active); puts 'Cleanup complete'"
```

---

### Test Case 6: Token Deactivation During Onboarding

**Objective:** Verify that if a user deactivates their only token during onboarding, they return to State 1.

**Setup:**
```ruby
# Run in Rails console or as oneliner:
bin/rails runner "u = User.find_by(email_address: 'test@example.com'); u.update!(state: :onboarding); u.feeds.destroy_all; t = u.access_tokens.first; t.update!(status: :active); puts 'Setup complete: Onboarding user with one active token, no feeds'"
```

**Expected State:**
- User state: `onboarding`
- Active tokens: 1
- Feeds: 0

**Test Steps:**
1. Sign in with email `test@example.com` and password `password123`
2. You should see "Welcome to Feeder" with "Add feed" button (State 2)
3. Navigate to "Access Tokens" page (from top navigation or settings)
4. Find the active token and deactivate it (click "Deactivate" or similar)
5. Navigate back to the Status page
6. Verify the page NOW displays:
   - State 1: "Welcome to Feeder" with "Add FreeFeed token" button
   - The message about adding a token (NOT about creating a feed)

**Cleanup:**
```bash
bin/rails runner "u = User.find_by(email_address: 'test@example.com'); u.update!(state: :active); u.access_tokens.first.update!(status: :active); puts 'User state reset'"
bin/rails db:seed
```

---

### Test Case 7: Active User Deletes All Feeds

**Objective:** Verify that an active user who deletes all feeds does NOT see "Welcome" message.

**Setup:**
```ruby
# Run in Rails console or as oneliner:
bin/rails runner "u = User.find_by(email_address: 'test@example.com'); u.update!(state: :active); u.access_tokens.first.update!(status: :active); puts 'Setup complete: Active user with feeds'"
```

**Expected State:**
- User state: `active`
- Active tokens: 1 or more
- Feeds: 1 or more

**Test Steps:**
1. Sign in with email `test@example.com` and password `password123`
2. Navigate to the Feeds page
3. Delete all feeds one by one
4. Navigate to the Status page
5. Verify the page displays:
   - Heading: "Status"
   - User statistics showing "0 feeds"
   - NO "Welcome to Feeder" message
   - NO special onboarding prompts
   - The page shows the normal dashboard with zero counts

**Cleanup:**
```bash
bin/rails db:seed
```

---

### Test Case 8: First Feed Creation Fails - State Not Changed

**Objective:** Verify that if feed creation fails during onboarding, the user remains in onboarding state.

**Setup:**
```ruby
# Run in Rails console or as oneliner:
bin/rails runner "u = User.find_by(email_address: 'test@example.com'); u.update!(state: :onboarding); u.feeds.destroy_all; u.access_tokens.first.update!(status: :active); puts 'Setup complete: Onboarding user ready to create first feed'"
```

**Expected State:**
- User state: `onboarding`
- Active tokens: 1 or more
- Feeds: 0

**Test Steps:**
1. Sign in with email `test@example.com` and password `password123`
2. You should see "Welcome to Feeder" with "Add feed" button
3. Click "Add feed"
4. Fill in the feed creation form with INVALID data:
   - URL: Leave empty or enter invalid URL
   - Click "Create Feed" (don't fill other required fields)
5. Verify you see validation errors
6. Navigate back to the Status page (click "Status" in navigation)
7. Verify the page STILL displays:
   - Heading: "Welcome to Feeder"
   - The onboarding State 2 message (create your first feed)
   - User is STILL in onboarding state

**Cleanup:**
```bash
bin/rails runner "u = User.find_by(email_address: 'test@example.com'); u.update!(state: :active); puts 'User state reset'"
bin/rails db:seed
```

---

### Test Case 9: Email Deactivation Warning Appears in All States

**Objective:** Verify that email deactivation warning appears regardless of onboarding state.

**Setup:**
```ruby
# Run in Rails console or as oneliner:
bin/rails runner "u = User.find_by(email_address: 'test@example.com'); u.update!(email_deactivated_at: Time.current, email_deactivation_reason: 'bounce'); puts 'Setup complete: User email deactivated'"
```

**Expected State:**
- User email is deactivated
- Any user state

**Test Steps:**
1. Sign in with email `test@example.com` and password `password123`
2. Navigate to the Status page
3. Verify that at the TOP of the page (before any other content):
   - Yellow/orange warning alert appears
   - Text: "Your email address is not receiving our emails."
   - Link to update email address
4. Verify the rest of the page displays normally (based on user's state)

**Cleanup:**
```ruby
bin/rails runner "u = User.find_by(email_address: 'test@example.com'); u.update!(email_deactivated_at: nil, email_deactivation_reason: nil); puts 'Cleanup complete'"
```

---

## Quick Reset to Default State

If tests leave the system in an inconsistent state, run:

```bash
bin/rails db:reset
bin/rails db:seed
```

This will restore the default development user and sample data.

## Notes for Browser Agents

- Each test case is independent - run the setup, perform the test, then run cleanup
- Setup scripts are provided as one-liners for easy copy-paste
- Expected states are documented to help verify preconditions
- All tests assume you're starting from a clean slate after running the setup script
- After each test, run the cleanup script before moving to the next test
