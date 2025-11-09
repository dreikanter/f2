# FreeFeed Access Token - Browser Test Scenarios

**Initial State**: User has registered an account but is currently signed out.

## 1. Authentication & Navigation

### Scenario 1.1: Sign in and navigate to access tokens
1. Navigate to `/sign_in`
2. Enter valid email and password
3. Click "Sign in"
4. **Expected**: Redirected to dashboard
5. Click "Settings" in navigation (or navigate to `/settings`)
6. Click "Access Tokens" tab (or navigate to `/settings/access_tokens`)
7. **Expected**: See access tokens page with empty state

---

## 2. Creating Access Tokens

### Scenario 2.1: Create first access token with name
1. **Precondition**: Signed in, on `/settings/access_tokens`, no tokens exist
2. Click "Add FreeFeed Access Token" button
3. **Expected**: Modal/form appears with fields:
   - Name (optional text input)
   - Host (dropdown with freefeed.net, candy.freefeed.net, beta.freefeed.net)
4. Enter name: "My First Token"
5. Select host: "freefeed.net (main)"
6. Click submit/create button
7. **Expected**:
   - Redirected or shown token creation success
   - See encrypted token value displayed (starting with "freefeed_token_")
   - See instructions to copy token and paste into FreeFeed
   - Status shows "Pending"

### Scenario 2.2: Create token without name
1. **Precondition**: Signed in, on `/settings/access_tokens`
2. Click "Add FreeFeed Access Token"
3. Leave name field blank
4. Select host: "freefeed.net (main)"
5. Click submit
6. **Expected**: Token created successfully with blank/null name displayed as empty

### Scenario 2.3: Create token for staging host
1. **Precondition**: Signed in, on `/settings/access_tokens`
2. Click "Add FreeFeed Access Token"
3. Enter name: "Staging Token"
4. Select host: "candy.freefeed.net (staging)"
5. Click submit
6. **Expected**: Token created with candy.freefeed.net as host

### Scenario 2.4: Create token for beta host
1. **Precondition**: Signed in, on `/settings/access_tokens`
2. Click "Add FreeFeed Access Token"
3. Enter name: "Beta Token"
4. Select host: "beta.freefeed.net (beta)"
5. Click submit
6. **Expected**: Token created with beta.freefeed.net as host

---

## 3. Token Validation

### Scenario 3.1: Successful token validation (requires valid FreeFeed token)
1. **Precondition**: Token created with status "Pending"
2. Copy the displayed token value
3. Open FreeFeed in new tab (https://freefeed.net)
4. Sign in to FreeFeed
5. Navigate to FreeFeed settings → App Tokens
6. Paste the copied token
7. Authorize the token with required scopes (read-my-info, manage-posts)
8. Return to F2 access tokens page
9. Click "Validate" button on the pending token
10. **Expected**:
    - Status changes to "Validating"
    - Page polls for updates
    - Status changes to "Active"
    - Username displays as "your_username@freefeed.net"
    - "Last used" timestamp appears
    - Token details show user info

### Scenario 3.2: Failed token validation (invalid/unauthorized token)
1. **Precondition**: Token created with status "Pending"
2. Do NOT authorize the token in FreeFeed (or use a revoked token)
3. Click "Validate" button
4. **Expected**:
    - Status changes to "Validating"
    - Status changes to "Inactive"
    - No username displayed
    - Error or inactive indicator shown

### Scenario 3.3: Validation polling behavior
1. **Precondition**: Token in "Validating" status
2. Stay on the page without navigating away
3. **Expected**:
    - Page automatically polls every few seconds
    - Status updates without manual refresh
    - Turbo Stream updates appear smoothly
    - Polling stops when status becomes "Active" or "Inactive"

---

## 4. Viewing Tokens

### Scenario 4.1: View empty state
1. **Precondition**: Signed in, no tokens created
2. Navigate to `/settings/access_tokens`
3. **Expected**:
    - Empty state component visible
    - Message like "No access tokens yet" or similar
    - "Add FreeFeed Access Token" button visible

### Scenario 4.2: View list of multiple tokens
1. **Precondition**: 3+ tokens created with different statuses
2. Navigate to `/settings/access_tokens`
3. **Expected**:
    - List of all tokens displayed
    - Each token shows:
      - Name (or blank if unnamed)
      - Host domain
      - Status badge (Pending/Active/Inactive)
      - Username@domain (if active)
      - Last used timestamp (if active)
    - Tokens sorted appropriately (newest first or by status)

### Scenario 4.3: View active token details
1. **Precondition**: At least one active token exists
2. Click on an active token in the list (or navigate to `/settings/access_tokens/{id}`)
3. **Expected**:
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
1. **Precondition**: Token created but not validated
2. Click on pending token
3. **Expected**:
    - Status: "Pending" with visual indicator (yellow/gray badge)
    - Token value displayed (encrypted, starts with "freefeed_token_")
    - Instructions to copy and paste into FreeFeed
    - Link or button to FreeFeed token creation page
    - "Validate" button
    - Actions: Edit name, Delete

### Scenario 4.5: View inactive token details
1. **Precondition**: Token that failed validation or was deactivated
2. Click on inactive token
3. **Expected**:
    - Status: "Inactive" with visual indicator (red/gray badge)
    - No username displayed
    - No user info
    - "Revalidate" button to retry validation
    - Actions: Edit name, Delete, Revalidate

---

## 5. Managing Tokens

### Scenario 5.1: Edit token name
1. **Precondition**: Token exists with name "Old Name"
2. Navigate to token details page
3. Click "Edit" or edit icon
4. Change name to "New Name"
5. Click "Save" or submit
6. **Expected**:
    - Name updated to "New Name"
    - Success message shown
    - Updated name visible in list and details

### Scenario 5.2: Edit token to remove name
1. **Precondition**: Token exists with a name
2. Navigate to edit form
3. Clear the name field (make it blank)
4. Click "Save"
5. **Expected**:
    - Name becomes blank/null
    - No error (name is optional)
    - Token shows without name in list

### Scenario 5.3: Delete token with confirmation
1. **Precondition**: Token exists
2. Navigate to token details or list
3. Click "Delete" button
4. **Expected**: Confirmation dialog appears
5. Click "Confirm" or "Delete"
6. **Expected**:
    - Token deleted from database
    - Removed from list
    - Success message shown
    - Redirected to tokens list

### Scenario 5.4: Cancel token deletion
1. **Precondition**: Token exists
2. Click "Delete" button
3. **Expected**: Confirmation dialog appears
4. Click "Cancel"
5. **Expected**:
    - Token NOT deleted
    - Remains in list
    - No changes made

### Scenario 5.5: Revalidate inactive token
1. **Precondition**: Token with status "Inactive"
2. Navigate to token details
3. Click "Revalidate" or "Validate" button
4. **Expected**:
    - Validation job triggered
    - Status changes to "Validating"
    - Polling begins
    - Eventually becomes "Active" (if authorized) or "Inactive" (if still invalid)

---

## 6. Multiple Tokens & Status Display

### Scenario 6.1: Multiple tokens with different hosts
1. **Precondition**: Create 3 tokens:
   - Token A: freefeed.net (active)
   - Token B: candy.freefeed.net (pending)
   - Token C: beta.freefeed.net (inactive)
2. Navigate to `/settings/access_tokens`
3. **Expected**:
    - All 3 tokens visible in list
    - Each shows correct host domain
    - Each shows correct status
    - Each has appropriate actions based on status

### Scenario 6.2: Same user with multiple active tokens for same host
1. **Precondition**: Create 2 tokens for freefeed.net, both validated
2. Navigate to tokens list
3. **Expected**:
    - Both tokens show "Active" status
    - Both show same username@freefeed.net
    - Both work independently
    - Can delete one without affecting the other

---

## 7. Authorization & Access Control

### Scenario 7.1: Attempt to access another user's token
1. **Precondition**: User A has token ID 123
2. Sign in as User B
3. Navigate to `/settings/access_tokens/123`
4. **Expected**:
    - Access denied (401/403 error)
    - Or redirected to User B's tokens list
    - Cannot view User A's token

### Scenario 7.2: Unauthenticated access to tokens page
1. **Precondition**: User signed out
2. Navigate to `/settings/access_tokens`
3. **Expected**:
    - Redirected to sign-in page
    - After signing in, redirected back to tokens page

---

## 8. Edge Cases & Error Handling

### Scenario 8.1: Network error during validation
1. **Precondition**: Token created, FreeFeed API temporarily down
2. Click "Validate"
3. **Expected**:
    - Validation job runs
    - After timeout/error, status becomes "Inactive"
    - Error logged (not necessarily shown to user)
    - User can retry validation later

### Scenario 8.2: Managed groups caching failure
1. **Precondition**: Token validated successfully, but managed_groups API fails
2. **Expected**:
    - Token still marked as "Active" (not deactivated due to cache failure)
    - User info cached
    - Managed groups section empty or shows error
    - Error logged

### Scenario 8.3: Token details expiration
1. **Precondition**: Token validated more than TTL ago (default: 1 hour)
2. Navigate to token details
3. **Expected**:
    - Cached details still shown (expired but present)
    - Or details refetched on next validation
    - Or indicator that data is stale

### Scenario 8.4: Concurrent validation of same token
1. **Precondition**: Token in "Pending" status
2. Open 2 browser tabs with same token
3. Click "Validate" in both tabs simultaneously
4. **Expected**:
    - No duplicate AccessTokenDetail records created
    - Locking prevents race condition
    - Both tabs eventually show same result

### Scenario 8.5: Token value display and security
1. **Precondition**: Token created
2. View token details page
3. **Expected**:
    - Token value visible only once (during creation) or with explicit "Show" action
    - Token stored encrypted in database
    - Token value starts with "freefeed_token_" prefix

---

## 9. UI/UX Validation

### Scenario 9.1: Responsive card footer spacing
1. Navigate to tokens list on mobile viewport (< 640px)
2. **Expected**: Card footer items left-aligned with proper gaps
3. Resize to desktop viewport (>= 640px)
4. **Expected**: Card footer items spaced with justify-between

### Scenario 9.2: Data attributes for testing
1. Inspect page elements
2. **Expected**: Components use `data-key` attributes for test selectors
   - Example: `[data-key="stats.total_feeds"]`
   - Example: `[data-key="empty-state.body"]`
   - Example: `[data-key="access-token.status"]`

### Scenario 9.3: UI text tone and clarity
1. Read all text on access tokens pages
2. **Expected**:
    - Friendly but professional tone
    - No overly technical jargon
    - No implementation details exposed ("wizard", "form", "modal")
    - Clear action-oriented language
    - Example: "Need to validate again?" instead of "Re-initialize validation wizard"

---

## 10. Integration with Feeds

### Scenario 10.1: Inactive token disables associated feeds
1. **Precondition**: Active token with 2 enabled feeds using it
2. Token validation fails (becomes inactive)
3. **Expected**:
    - Token status changes to "Inactive"
    - Associated feeds automatically disabled
    - Feeds show disabled state in feeds list

### Scenario 10.2: Deleting token affects feeds
1. **Precondition**: Active token with associated feeds
2. Delete the token
3. **Expected**:
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
