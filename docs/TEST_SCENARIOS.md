# FreeFeed Access Token - Browser Test Scenarios

**Initial State**: User has registered an account but is currently signed out.

## 1. Authentication & Navigation

### Scenario 1.1: Sign in and navigate to access tokens

**Steps**:
1. Navigate to the root page and click "Sign in" button
2. Enter valid email and password
3. Click "Sign in"
4. Select "Tokens" from the dropdown menu in the navbar

**Expected**:
- Access tokens page is displayed
- Empty state component visible
- Message like "No access tokens yet" or similar
- "Add FreeFeed Access Token" button visible

---

## 2. Creating Access Tokens

### Scenario 2.1: Create first access token with name

**Preconditions**:
- User is signed in
- User is on access tokens page
- No tokens exist

**Steps**:
1. Click "Add FreeFeed Access Token" button
2. Enter name: "My First Token"
3. Select host: "freefeed.net (main)"
4. Click submit/create button

**Expected**:
- Modal/form appears with fields:
  - Name (optional text input)
  - Host (dropdown with freefeed.net, candy.freefeed.net, beta.freefeed.net)
- Redirected or shown token creation success
- See encrypted token value displayed (starting with "freefeed_token_")
- See instructions to copy token and paste into FreeFeed
- Status shows "Pending"

### Scenario 2.2: Create token without name

**Preconditions**:
- User is signed in
- User is on access tokens page

**Steps**:
1. Click "Add FreeFeed Access Token"
2. Leave name field blank
3. Select host: "freefeed.net (main)"
4. Click submit

**Expected**:
- Token created successfully with blank/null name displayed as empty

### Scenario 2.3: Create token for staging host

**Preconditions**:
- User is signed in
- User is on access tokens page

**Steps**:
1. Click "Add FreeFeed Access Token"
2. Enter name: "Staging Token"
3. Select host: "candy.freefeed.net (staging)"
4. Click submit

**Expected**:
- Token created with candy.freefeed.net as host

### Scenario 2.4: Create token for beta host

**Preconditions**:
- User is signed in
- User is on access tokens page

**Steps**:
1. Click "Add FreeFeed Access Token"
2. Enter name: "Beta Token"
3. Select host: "beta.freefeed.net (beta)"
4. Click submit

**Expected**:
- Token created with beta.freefeed.net as host

---

## 3. Token Validation

### Scenario 3.1: Successful token validation (requires valid FreeFeed token)

**Preconditions**:
- User is signed in
- User has just created a token

**Steps**:
1. Copy the displayed token value
2. Open FreeFeed in new tab (https://freefeed.net)
3. Sign in to FreeFeed
4. Navigate to FreeFeed settings → App Tokens
5. Paste the copied token
6. Authorize the token with required scopes (read-my-info, manage-posts)
7. Return to F2 access tokens page
8. Wait for background job to validate the token

**Expected**:
- Token initially shows "Pending" status briefly
- Status automatically changes to "Validating" (transient state)
- Page polls for updates
- Status changes to "Active"
- Username displays as "your_username@freefeed.net"
- "Last used" timestamp appears
- Token details show user info

### Scenario 3.2: Failed token validation (invalid/unauthorized token)

**Preconditions**:
- User is signed in
- User has just created a token

**Steps**:
1. Do NOT authorize the token in FreeFeed (or use a revoked token)
2. Wait for background job to attempt validation

**Expected**:
- Token initially shows "Pending" status briefly
- Status automatically changes to "Validating" (transient state)
- Status changes to "Inactive"
- No username displayed
- Error or inactive indicator shown

### Scenario 3.3: Validation polling behavior

**Preconditions**:
- User is signed in
- User has just created a token
- Background validation job is running

**Steps**:
1. Stay on the page without navigating away
2. Observe the automatic status updates

**Expected**:
- Page automatically polls every few seconds
- Status updates without manual refresh (Pending → Validating → Active/Inactive)
- Turbo Stream updates appear smoothly
- Polling stops when status becomes "Active" or "Inactive"

---

## 4. Viewing Tokens

### Scenario 4.1: View empty state

**Preconditions**:
- User is signed in
- No tokens created

**Steps**:
1. Select "Tokens" from the dropdown menu in the navbar

**Expected**:
- Empty state component visible
- Message like "No access tokens yet" or similar
- "Add FreeFeed Access Token" button visible

### Scenario 4.2: View list of multiple tokens

**Preconditions**:
- User is signed in
- 3+ tokens created with different statuses

**Steps**:
1. Navigate to access tokens page

**Expected**:
- List of all tokens displayed
- Each token shows:
  - Name (or blank if unnamed)
  - Host domain
  - Status badge (Pending/Active/Inactive)
  - Username@domain (if active)
  - Last used timestamp (if active)
- Tokens sorted appropriately (newest first or by status)

### Scenario 4.3: View active token details

**Preconditions**:
- User is signed in
- At least one active token exists

**Steps**:
1. Click on an active token in the list

**Expected**:
- Token name displayed
- Status: "Active" with visual indicator (green badge/icon)
- Host: full URL or domain
- Owner: "username@freefeed.net"
- Last used: timestamp
- User info section showing:
  - Username
  - Screen name (if available)
- Managed groups section (if user manages groups on FreeFeed)
- Actions: Edit name, Delete, Revalidate

### Scenario 4.4: View pending token details

**Preconditions**:
- User is signed in
- User has just created a token
- Background validation has not yet completed

**Steps**:
1. Click on token immediately after creation (while still pending)

**Expected**:
- Status: "Pending" with visual indicator (yellow/gray badge) - transient state
- Token value displayed (encrypted, starts with "freefeed_token_")
- Instructions to copy and paste into FreeFeed
- Link or button to FreeFeed token creation page
- Actions: Edit name, Delete
- Note: This state is brief and will automatically transition to Active or Inactive

### Scenario 4.5: View inactive token details

**Preconditions**:
- User is signed in
- Token that failed validation or was deactivated

**Steps**:
1. Click on inactive token

**Expected**:
- Status: "Inactive" with visual indicator (red/gray badge)
- No username displayed
- No user info
- "Revalidate" button to retry validation
- Actions: Edit name, Delete, Revalidate

---

## 5. Managing Tokens

### Scenario 5.1: Edit token name

**Preconditions**:
- User is signed in
- Token exists with name "Old Name"

**Steps**:
1. Navigate to token details page
2. Click "Edit" or edit icon
3. Change name to "New Name"
4. Click "Save" or submit

**Expected**:
- Name updated to "New Name"
- Success message shown
- Updated name visible in list and details

### Scenario 5.2: Edit token to remove name

**Preconditions**:
- User is signed in
- Token exists with a name

**Steps**:
1. Navigate to edit form
2. Clear the name field (make it blank)
3. Click "Save"

**Expected**:
- Name becomes blank/null
- No error (name is optional)
- Token shows without name in list

### Scenario 5.3: Delete token with confirmation

**Preconditions**:
- User is signed in
- Token exists

**Steps**:
1. Navigate to token details or list
2. Click "Delete" button
3. Click "Confirm" or "Delete" in confirmation dialog

**Expected**:
- Confirmation dialog appears before deletion
- Token deleted from database
- Removed from list
- Success message shown
- Redirected to tokens list

### Scenario 5.4: Cancel token deletion

**Preconditions**:
- User is signed in
- Token exists

**Steps**:
1. Click "Delete" button
2. Click "Cancel" in confirmation dialog

**Expected**:
- Confirmation dialog appears
- Token NOT deleted
- Remains in list
- No changes made

### Scenario 5.5: Revalidate inactive token

**Preconditions**:
- User is signed in
- Token with status "Inactive" (validation previously failed)

**Steps**:
1. Navigate to token details
2. Click "Revalidate" button to trigger a new validation attempt

**Expected**:
- Background validation job triggered
- Status automatically changes to "Validating" (transient state)
- Page polls for updates
- Status eventually becomes "Active" (if now authorized in FreeFeed) or remains "Inactive" (if still invalid)

---

## 6. Multiple Tokens & Status Display

### Scenario 6.1: Multiple tokens with different hosts

**Preconditions**:
- User is signed in
- Create 3 tokens:
  - Token A: freefeed.net (active)
  - Token B: candy.freefeed.net (pending)
  - Token C: beta.freefeed.net (inactive)

**Steps**:
1. Navigate to access tokens page

**Expected**:
- All 3 tokens visible in list
- Each shows correct host domain
- Each shows correct status
- Each has appropriate actions based on status

### Scenario 6.2: Same user with multiple active tokens for same host

**Preconditions**:
- User is signed in
- Create 2 tokens for freefeed.net, both validated

**Steps**:
1. Navigate to tokens list

**Expected**:
- Both tokens show "Active" status
- Both show same username@freefeed.net
- Both work independently
- Can delete one without affecting the other

---

## 7. Authorization & Access Control

### Scenario 7.1: Attempt to access another user's token

**Preconditions**:
- User A has token ID 123
- User B has an account

**Steps**:
1. Sign in as User B
2. Attempt to access User A's token (e.g., by directly navigating to token ID 123)

**Expected**:
- Access denied (401/403 error)
- Or redirected to User B's tokens list
- Cannot view User A's token

### Scenario 7.2: Unauthenticated access to tokens page

**Preconditions**:
- User is signed out

**Steps**:
1. Attempt to access the tokens page (e.g., by selecting "Tokens" from navbar or direct URL)

**Expected**:
- Redirected to sign-in page
- After signing in, redirected back to tokens page

---

## 8. Edge Cases & Error Handling

### Scenario 8.1: Network error during validation

**Preconditions**:
- User is signed in
- User has just created a token
- FreeFeed API temporarily down

**Steps**:
1. Wait for background validation job to run

**Expected**:
- Validation job runs automatically
- After timeout/error, status becomes "Inactive"
- Error logged (not necessarily shown to user)
- User can click "Revalidate" button to retry validation later

### Scenario 8.2: Managed groups caching failure

**Preconditions**:
- User is signed in
- Token validated successfully
- managed_groups API fails

**Expected**:
- Token still marked as "Active" (not deactivated due to cache failure)
- User info cached
- Managed groups section empty or shows error
- Error logged

### Scenario 8.3: Token details expiration

**Preconditions**:
- User is signed in
- Token validated more than TTL ago (default: 1 hour)

**Steps**:
1. Navigate to token details

**Expected**:
- Cached details still shown (expired but present)
- Or details refetched on next validation
- Or indicator that data is stale

### Scenario 8.4: Concurrent validation of same token

**Preconditions**:
- User is signed in
- User has just created a token

**Steps**:
1. Open 2 browser tabs showing the same token details
2. Background validation job runs automatically

**Expected**:
- No duplicate AccessTokenDetail records created
- Locking prevents race condition
- Both tabs automatically update and eventually show same validation result
- Status transitions visible in both tabs (Pending → Validating → Active/Inactive)

### Scenario 8.5: Token value display and security

**Preconditions**:
- User is signed in
- Token created

**Steps**:
1. View token details page

**Expected**:
- Token value visible only once (during creation) or with explicit "Show" action
- Token stored encrypted in database
- Token value starts with "freefeed_token_" prefix

---

## 9. UI/UX Validation

### Scenario 9.1: Responsive card footer spacing

**Preconditions**:
- User is signed in
- User is on access tokens page

**Steps**:
1. Navigate to tokens list on mobile viewport (< 640px)
2. Resize to desktop viewport (>= 640px)

**Expected**:
- On mobile: Card footer items left-aligned with proper gaps
- On desktop: Card footer items spaced with justify-between

### Scenario 9.2: Data attributes for testing

**Preconditions**:
- User is signed in
- User is on access tokens page

**Steps**:
1. Inspect page elements

**Expected**:
- Components use `data-key` attributes for test selectors
- Example: `[data-key="stats.total_feeds"]`
- Example: `[data-key="empty-state.body"]`
- Example: `[data-key="access-token.status"]`

### Scenario 9.3: UI text tone and clarity

**Preconditions**:
- User is signed in
- User is on access tokens page

**Steps**:
1. Read all text on access tokens pages

**Expected**:
- Friendly but professional tone
- No overly technical jargon
- No implementation details exposed ("wizard", "form", "modal")
- Clear action-oriented language
- Example: "Need to validate again?" instead of "Re-initialize validation wizard"

---

## 10. Integration with Feeds

### Scenario 10.1: Inactive token disables associated feeds

**Preconditions**:
- User is signed in
- Active token with 2 enabled feeds using it

**Steps**:
1. Token validation fails (becomes inactive)

**Expected**:
- Token status changes to "Inactive"
- Associated feeds automatically disabled
- Feeds show disabled state in feeds list

### Scenario 10.2: Deleting token affects feeds

**Preconditions**:
- User is signed in
- Active token with associated feeds

**Steps**:
1. Delete the token

**Expected**:
- Token deleted
- Associated feeds orphaned or marked as needing new token
- User notified of impact

---

## Test Data Setup

For comprehensive testing, create this dataset:

1. **User Account**: email: test@example.com, password: password123
2. **Tokens**:
   - Token 1: "Production Token", freefeed.net, Active, owner: testuser@freefeed.net
   - Token 2: "Staging Test", candy.freefeed.net, Pending
   - Token 3: (no name), freefeed.net, Inactive
   - Token 4: "Beta Access", beta.freefeed.net, Active, owner: betauser@beta.freefeed.net
3. **Feeds** (if testing integration):
   - Feed 1: Using Token 1, enabled
   - Feed 2: Using Token 1, enabled
   - Feed 3: Using Token 4, enabled

---

## Validation Checklist

For each scenario:
- [ ] Page loads without errors
- [ ] All UI elements render correctly
- [ ] Actions complete successfully
- [ ] Success/error messages display appropriately
- [ ] Navigation works as expected
- [ ] Data persists correctly
- [ ] Authorization enforced
- [ ] No console errors
- [ ] Responsive design works across viewports
- [ ] Turbo Streams update correctly
- [ ] Polling starts and stops appropriately
