# Browser Agent Testing Guide - Feed Management

This guide provides self-contained test cases for automated browser testing of the feed creation and editing workflow. Each test case is independent and can be executed in any order.

## Prerequisites

### Environment Setup

The application must be running with seed data loaded:

```bash
# Start PostgreSQL
su - postgres -c "/usr/lib/postgresql/16/bin/pg_ctl start -D /var/lib/postgresql/16/main -l /tmp/postgres.log -o '-c config_file=/etc/postgresql/16/main/postgresql.conf'"

# Setup database with seed data
bin/rails db:create db:migrate db:seed

# Start Rails server
bin/rails server
```

### Seed Data Reference

The seed script creates:
- **User**: `test@example.com` / `password123`
- **Active Tokens**: "Active Token 1", "Active Token 2", "Active Token 3" (all for testuser1, testuser2, testuser3 @ freefeed.net)
- **Inactive Tokens**: "Inactive Token 4", "Inactive Token 5" (testuser4, testuser5)
- **Sample Feeds**: 5 feeds (Google Open Source Blog, AWS Open Source Blog, Cloud Native Computing Foundation, NIST News Feed, arXiv Computer Science)

---

## Test Case 1: Create Enabled Feed - Happy Path

**Objective:** Verify successful creation of an enabled feed with all valid inputs.

**Prerequisites:** User is signed out.

**Steps:**
1. Navigate to `http://localhost:3000`
2. Click "Sign in" link
3. Enter email: `test@example.com`
4. Enter password: `password123`
5. Click "Sign in" button
6. Navigate to `http://localhost:3000/feeds/new`
7. In the "Feed URL" field, enter: `https://xkcd.com/rss.xml`
8. Click "Identify Feed Format" button
9. Wait for form to expand (loading indicator should appear then disappear, ~1-2 seconds)
10. Verify the "Feed Name" field is auto-populated (should contain "xkcd")
11. In the "Target Group" field, enter: `testgroup`
12. Keep "Check for new posts every" at default "1 hour"
13. Verify "Enable feed" checkbox is checked
14. Verify submit button shows "Create and Enable Feed"
15. Click "Create and Enable Feed" button

**Expected Results:**
- Page redirects to feed show page (URL pattern: `/feeds/[number]`)
- Success message appears (green background): "Feed '[name]' was successfully created and is now active. New posts will be checked every 1 hour and published to testgroup."
- Page shows feed details with "Edit" button visible
- "Disable" button is present (feed is enabled)

**Cleanup:** None required (feed remains for other tests).

---

## Test Case 2: Create Disabled Feed

**Objective:** Verify creation of a disabled feed and dynamic button label change.

**Prerequisites:** User is signed out.

**Steps:**
1. Navigate to `http://localhost:3000`
2. Sign in with `test@example.com` / `password123`
3. Navigate to `http://localhost:3000/feeds/new`
4. Enter URL: `https://example.com/disabled-test.xml`
5. Click "Identify Feed Format"
6. Wait for form expansion
7. Change "Feed Name" to: `My Disabled Feed`
8. Enter "Target Group": `testgroup`
9. Uncheck the "Enable feed" checkbox
10. Verify submit button text changes to "Create Feed"
11. Click "Create Feed" button

**Expected Results:**
- Redirects to feed show page
- Success message: "Feed 'My Disabled Feed' was successfully created but is currently disabled. Enable it from the feed page when you're ready to start importing posts."
- "Enable" button is present (not "Disable")
- Feed appears in feeds list as disabled/inactive

**Cleanup:** None required.

---

## Test Case 3: Blocked State - No Active Tokens

**Objective:** Verify blocked state when user has no active access tokens.

**Prerequisites:** User is signed out, all tokens must be inactive.

**Setup Steps:**
1. Navigate to `http://localhost:3000`
2. Sign in with `test@example.com` / `password123`
3. Navigate to `http://localhost:3000/settings/access_tokens`
4. For each active token (Active Token 1, 2, 3):
   - Click the token row to expand details
   - Click "Deactivate" button
   - Confirm in modal
5. Verify all tokens show as "Inactive"

**Test Steps:**
1. Navigate to `http://localhost:3000/feeds/new`

**Expected Results:**
- Warning alert with amber/yellow background is displayed
- Message text: "You need to have an active FreeFeed access token before creating a feed."
- "Add Access Token" button is visible
- "Cancel" button is visible
- NO URL input field or "Identify Feed Format" button is shown
- No card border around the content

**Cleanup Steps:**
1. Navigate to `http://localhost:3000/settings/access_tokens`
2. For each inactive token:
   - Click the token row
   - Click "Activate" button
   - Confirm in modal
3. Verify tokens are active again

---

## Test Case 4: Validation Error - Missing Target Group

**Objective:** Verify validation error handling preserves all user input on the expanded form.

**Prerequisites:** User is signed out.

**Steps:**
1. Navigate to `http://localhost:3000`
2. Sign in with `test@example.com` / `password123`
3. Navigate to `http://localhost:3000/feeds/new`
4. Enter URL: `https://example.com/validation-test.xml`
5. Click "Identify Feed Format"
6. Wait for form expansion
7. Change "Feed Name" to: `Validation Test Feed`
8. Change "Check for new posts every" to: `2 hours`
9. Leave "Target Group" field empty (do not enter anything)
10. Ensure "Enable feed" checkbox is checked
11. Click "Create and Enable Feed" button

**Expected Results:**
- Page stays on `/feeds/new` (does not redirect)
- HTTP status is 422 (Unprocessable Entity)
- **Expanded form remains visible** (NOT collapsed URL-only form)
- All input values are preserved:
  - URL field shows: `https://example.com/validation-test.xml` (disabled/grayed)
  - Feed Type shows: "RSS/Atom Feed" (disabled)
  - Feed Name shows: `Validation Test Feed`
  - Schedule shows: `2 hours`
  - "Enable feed" checkbox remains checked
- Red error message below "Target Group" field: "can't be blank" or "must be filled"
- Error text uses red color (ff-form-error class)

**Verification (Fix and Retry):**
1. Enter "Target Group": `testgroup`
2. Click "Create and Enable Feed" button
3. Should successfully create feed and redirect to show page

**Cleanup:** None required.

---

## Test Case 5: Validation Error - Missing Feed Name

**Objective:** Verify validation error when feed name is missing.

**Prerequisites:** User is signed out.

**Steps:**
1. Navigate to `http://localhost:3000`
2. Sign in with `test@example.com` / `password123`
3. Navigate to `http://localhost:3000/feeds/new`
4. Enter URL: `https://example.com/name-test.xml`
5. Click "Identify Feed Format"
6. Wait for form expansion
7. Clear the "Feed Name" field completely (delete all text)
8. Enter "Target Group": `testgroup`
9. Click "Create and Enable Feed" button

**Expected Results:**
- Page stays on `/feeds/new` with 422 status
- Expanded form remains visible
- Red error message below "Feed Name" field: "can't be blank"
- Help text changes to: "We couldn't automatically detect a name. Please enter one."
- Target Group value `testgroup` is preserved
- All other inputs preserved (URL, schedule, checkbox)

**Cleanup:** None required.

---

## Test Case 6: Edit Feed - Happy Path

**Objective:** Verify successful editing of an existing feed.

**Prerequisites:** User is signed out. At least one feed exists (from seed data: "Google Open Source Blog").

**Steps:**
1. Navigate to `http://localhost:3000`
2. Sign in with `test@example.com` / `password123`
3. Navigate to `http://localhost:3000/feeds`
4. Click on "Google Open Source Blog" feed in the list
5. On the feed show page, click the "Edit" button
6. Verify informational notice (blue background) is displayed with text: "Feed URL and Type cannot be changed after creation. To use a different URL, create a new feed."
7. Verify "Feed URL" field is disabled and grayed out with value: `https://feeds.feedburner.com/GoogleOpenSourceBlog`
8. Verify "Feed Type" field is disabled showing "RSS/Atom Feed"
9. Change "Feed Name" to: `Google OSS Blog - Updated`
10. Change "Check for new posts every" to: `12 hours`
11. Change "Target Group" to: `google-oss-updated`
12. Click "Update Feed Configuration" button

**Expected Results:**
- Redirects back to feed show page
- Success message: "Feed 'Google OSS Blog - Updated' was successfully updated."
- If feed was enabled, additional text: "Changes will take effect on the next scheduled refresh."
- Feed name on page shows updated value
- Edit button still visible

**Cleanup:** None required.

---

## Test Case 7: Edit Feed - Validation Error

**Objective:** Verify validation error handling on edit form preserves user input.

**Prerequisites:** User is signed out. "AWS Open Source Blog" feed exists (from seed data).

**Steps:**
1. Navigate to `http://localhost:3000`
2. Sign in with `test@example.com` / `password123`
3. Navigate to `http://localhost:3000/feeds`
4. Click on "AWS Open Source Blog" feed
5. Click "Edit" button
6. Clear the "Feed Name" field (delete all text)
7. Click "Update Feed Configuration" button

**Expected Results:**
- Page stays on edit form (URL pattern: `/feeds/[number]/edit`)
- HTTP status is 422
- Red error message below "Feed Name": "can't be blank"
- URL field remains disabled showing original URL
- Feed Type field remains disabled
- Target Group and Schedule values are preserved
- No changes are saved to the feed

**Verification (Fix and Retry):**
1. Enter new Feed Name: `AWS OSS Blog`
2. Click "Update Feed Configuration"
3. Should successfully update and redirect to show page

**Cleanup:** None required.

---

## Test Case 8: Edit Feed - Read-only Fields Cannot Be Changed

**Objective:** Verify URL and Feed Type cannot be modified during editing (enforcement check).

**Prerequisites:** User is signed out. Any feed exists (from seed data).

**Steps:**
1. Navigate to `http://localhost:3000`
2. Sign in with `test@example.com` / `password123`
3. Navigate to `http://localhost:3000/feeds`
4. Click on any feed in the list
5. Click "Edit" button
6. Inspect the "Feed URL" field using browser DevTools
7. Verify the field has `disabled` attribute
8. Inspect the "Feed Type" field
9. Verify it has `disabled` attribute
10. Note the original URL value
11. Change "Feed Name" to something new
12. Click "Update Feed Configuration"
13. Click "Edit" button again
14. Verify URL remains unchanged

**Expected Results:**
- Feed URL input field has `disabled="disabled"` attribute
- Feed Type input field has `disabled="disabled"` attribute
- Both fields have grayed background (bg-slate-100 class)
- URL value cannot be modified through the UI
- After save, URL remains the same as before edit

**Cleanup:** None required.

---

## Test Case 9: Button Label Dynamic Update (Stimulus)

**Objective:** Verify submit button label changes based on "Enable feed" checkbox state.

**Prerequisites:** User is signed out.

**Steps:**
1. Navigate to `http://localhost:3000`
2. Sign in with `test@example.com` / `password123`
3. Navigate to `http://localhost:3000/feeds/new`
4. Enter any URL: `https://example.com/stimulus-test.xml`
5. Click "Identify Feed Format"
6. Wait for form expansion
7. Observe submit button text (should show "Create and Enable Feed")
8. Uncheck "Enable feed" checkbox
9. Observe submit button text change
10. Check "Enable feed" checkbox again
11. Observe submit button text change
12. Repeat toggling 2-3 times

**Expected Results:**
- When checkbox is **checked**: Button shows "Create and Enable Feed"
- When checkbox is **unchecked**: Button shows "Create Feed"
- Text changes **immediately** when checkbox is toggled (no delay)
- Changes are smooth and instant (JavaScript/Stimulus working correctly)

**Cleanup:** Cancel form (click "Cancel" button).

---

## Test Case 10: Groups Loading State

**Objective:** Verify target group selector shows loading state while fetching groups.

**Prerequisites:** User is signed out.

**Steps:**
1. Navigate to `http://localhost:3000`
2. Sign in with `test@example.com` / `password123`
3. Navigate to `http://localhost:3000/feeds/new`
4. Enter URL: `https://example.com/groups-test.xml`
5. Click "Identify Feed Format"
6. Wait for form expansion
7. Immediately observe the "Target Group" field
8. Wait 1-2 seconds and observe again

**Expected Results:**
- Initially (right after form expands):
  - "Target Group" field shows as a select dropdown
  - Field is disabled
  - Placeholder shows "Loading groups..."
  - Field has grayed appearance
- After loading completes (~1-2 seconds):
  - Field becomes enabled
  - Placeholder changes or field becomes editable
  - User can interact with the field

**Cleanup:** Click "Cancel" button.

---

## Test Case 11: Feed Navigation and Edit Access

**Objective:** Verify Edit button is accessible from feed show page.

**Prerequisites:** User is signed out. At least one feed exists (from seed data).

**Steps:**
1. Navigate to `http://localhost:3000`
2. Sign in with `test@example.com` / `password123`
3. Navigate to `http://localhost:3000/feeds`
4. Click on any feed name in the list
5. On the feed show page, locate the "Edit" button in the page header
6. Verify it appears alongside other action buttons (Disable/Enable, Preview)
7. Click the "Edit" button
8. Verify edit form loads
9. Click "Cancel" button

**Expected Results:**
- "Edit" button is visible in the page header on feed show page
- Button has styling: `ff-button ff-button--secondary ff-button--compact`
- Button appears before Disable/Enable and Preview buttons
- Clicking Edit button navigates to `/feeds/[id]/edit`
- Edit form loads successfully
- Cancel button returns to feed show page

**Cleanup:** None required.

---

## Test Case 12: Create Feed - Schedule Interval Selection

**Objective:** Verify all schedule interval options are available and can be selected.

**Prerequisites:** User is signed out.

**Steps:**
1. Navigate to `http://localhost:3000`
2. Sign in with `test@example.com` / `password123`
3. Navigate to `http://localhost:3000/feeds/new`
4. Enter URL: `https://example.com/schedule-test.xml`
5. Click "Identify Feed Format"
6. Wait for form expansion
7. Click on "Check for new posts every" dropdown
8. Verify all options are present:
   - 10 minutes
   - 20 minutes
   - 30 minutes
   - 1 hour
   - 2 hours
   - 6 hours
   - 12 hours
   - 1 day
   - 2 days
9. Select "6 hours"
10. Enter "Feed Name": `Schedule Test`
11. Enter "Target Group": `testgroup`
12. Click "Create and Enable Feed"

**Expected Results:**
- All 9 schedule interval options are visible in dropdown
- Default selection is "1 hour"
- Selected value "6 hours" is preserved after selection
- Feed is created successfully with selected schedule
- Success message mentions "every 6 hours"

**Cleanup:** None required.

---

## Test Case 13: Visual Consistency Check

**Objective:** Verify form styling consistency across feed and access token forms.

**Prerequisites:** User is signed out.

**Steps:**
1. Navigate to `http://localhost:3000`
2. Sign in with `test@example.com` / `password123`
3. Navigate to `http://localhost:3000/feeds/new`
4. Enter URL: `https://example.com/style-test.xml`
5. Click "Identify Feed Format"
6. Wait for form expansion
7. Inspect form styling (no card border, proper spacing)
8. Navigate to `http://localhost:3000/settings/access_tokens/new`
9. Compare form styling

**Expected Results:**
- **Both forms** have NO card border (no `ff-card` wrapper with border)
- Both use `ff-card__footer` class for button sections
- Buttons are full-width (not compact in footer)
- Consistent spacing between form fields
- Both use same `ff-form-input` class for inputs
- Alert boxes (if any) use standard `ff-alert` classes
- Visual layout and spacing match exactly

**Cleanup:** Click Cancel on both forms.

---

## Test Case 14: Input Field Height Consistency

**Objective:** Verify all form inputs (text, select) have identical height.

**Prerequisites:** User is signed out.

**Steps:**
1. Navigate to `http://localhost:3000`
2. Sign in with `test@example.com` / `password123`
3. Navigate to `http://localhost:3000/feeds/new`
4. Enter URL: `https://example.com/height-test.xml`
5. Click "Identify Feed Format"
6. Wait for form expansion
7. Open browser DevTools (F12)
8. Inspect these elements:
   - "Feed Name" text input
   - "FreeFeed Account" select dropdown
   - "Check for new posts every" select dropdown
9. Check computed height in DevTools for each element

**Expected Results:**
- All three elements have class `ff-form-input`
- All three elements have class `leading-normal`
- All three elements have identical computed height (~44px)
- No visible height differences between text inputs and select dropdowns
- Alignment is consistent across all fields

**Cleanup:** Click "Cancel" button.

---

## Test Case 15: Access Token Selection on Create

**Objective:** Verify access token selector displays active tokens and handles selection.

**Prerequisites:** User is signed out. At least 2 active tokens exist (from seed data: Active Token 1, 2, 3).

**Steps:**
1. Navigate to `http://localhost:3000`
2. Sign in with `test@example.com` / `password123`
3. Navigate to `http://localhost:3000/feeds/new`
4. Enter URL: `https://example.com/token-test.xml`
5. Click "Identify Feed Format"
6. Wait for form expansion
7. Click on "FreeFeed Account" dropdown
8. Verify available options
9. Select "Active Token 2"
10. Verify selection is reflected
11. Enter "Feed Name": `Token Test`
12. Enter "Target Group": `testgroup`
13. Click "Create and Enable Feed"

**Expected Results:**
- "FreeFeed Account" dropdown shows all active tokens
- Format: "freefeed.net - testuser1", "freefeed.net - testuser2", "freefeed.net - testuser3"
- Inactive tokens do NOT appear in dropdown
- Selected token is clearly indicated
- Feed is created successfully with selected token
- Can verify token association on feed show page

**Cleanup:** None required.

---

## Success Criteria Checklist

After running all test cases, verify:

- [ ] Feed creation works with enabled state
- [ ] Feed creation works with disabled state
- [ ] Blocked state shows when no active tokens exist
- [ ] Validation errors preserve all user input on expanded form
- [ ] Feed editing works and saves changes correctly
- [ ] URL and Feed Type are read-only on edit form
- [ ] Edit button is accessible from feed show page
- [ ] Button labels toggle dynamically with checkbox (Stimulus)
- [ ] Groups loading state displays correctly
- [ ] All schedule intervals are available and selectable
- [ ] Form styling is consistent with other forms in the app
- [ ] Input fields (text and select) have identical heights
- [ ] Only active access tokens appear in dropdown
- [ ] Success and error messages display correctly
- [ ] Navigation flows work correctly (redirects, cancel buttons)

---

## Notes for Browser Agents

- Each test case is self-contained and can run independently
- Tests can be executed in any order
- No test case requires completion of another test case
- Cleanup steps are minimal (most tests don't need cleanup)
- All verification points can be checked via DOM inspection
- No Rails console access required - all checks are UI-based
- Wait times for async operations (loading, form expansion) are specified
- Expected CSS classes are documented for precise verification
