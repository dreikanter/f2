# Manual Feed Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the auto-running preview turbo-frame on the feed form with a user-initiated "Preview" button that opens a modal driving the existing preview stack, and decouple previewing from enabling.

**Architecture:** The backend (`FeedPreviewsController` show/create, `FeedPreviewJob`, `FeedPreviewWorkflow`) is unchanged. We (1) delete the enable gate so preview is optional, (2) replace the lazy frame in `_form_expanded` with a button + a `ModalComponent` hosting the same `feed-preview` turbo-frame + polling host, and (3) rewire refresh and modal-close so the single preview host behaves correctly. Front-end interactivity is verified in a real browser; server-rendered structure is covered by request tests.

**Tech Stack:** Rails (edge), Hotwire (Turbo + Stimulus), ViewComponent, FactoryBot/Minitest, RuboCop.

**Conventions (carry over):** Atomic commits, imperative subjects ≤50 chars. Run `bin/rails test` + `bin/rubocop -f github` before every commit. Trailing newline on every source file. Work happens on branch `manual-feed-preview` (already created off `main`).

---

## File Structure

**Backend (delete the enable gate, make preview optional):**
- Modify `app/models/feed.rb` — remove `enabling_requires_recent_preview` + its validator; simplify `enable`; rename window constant; generalize `can_be_previewed?`.
- Modify `app/models/feed_preview.rb` — remove `fresh_ready`.
- Modify `app/controllers/feed_previews_controller.rb` — rename window constant in `stale_ready?`.
- Modify `app/jobs/prune_feed_previews_job.rb` — comment only.
- Modify tests: `test/models/feed_test.rb`, `test/models/feed_preview_test.rb`, `test/controllers/feed_previews_controller_test.rb`, `test/controllers/feeds_controller_test.rb`.
- Delete `test/support/preview_helpers.rb` (only the gate used it) — verify no other callers first.

**Front-end (button + modal):**
- Modify `app/views/feeds/_form_expanded.html.erb` — replace the lazy frame with the button + modal; expose source/shape data.
- Create `app/javascript/controllers/preview_button_controller.js` — availability, open-with-src, clear-on-close.
- Modify `app/javascript/controllers/preview_controller.js` — slim to refresh-via-`closest`.
- Modify `app/javascript/controllers/modal_controller.js` — dispatch a generic `modal:hide` on close.
- Modify `app/views/feed_previews/_failed.html.erb` — drop `button_to` for a JS Try-again.
- Modify `app/views/feeds/_candidate_chooser.html.erb` + delete `app/javascript/controllers/candidate_chooser_controller.js` — drop the dead dispatch.

---

## Task 1: Remove the enable-preview gate from the Feed model

**Files:**
- Modify: `app/models/feed.rb`
- Test: `test/models/feed_test.rb:560-690` (the "T018" preview-gate block)

- [ ] **Step 1: Replace the gate tests with optional-preview tests**

In `test/models/feed_test.rb`, delete the entire block from the `# T018: enabling_requires_recent_preview validation` comment (line 560) through the `"should not require a preview when toggling state on unchanged enabled feed"` test's closing `end` (line 690), and replace it with:

```ruby
  # Preview is optional and does not gate enabling.
  def preview_user
    @preview_user ||= create(:user)
  end

  def access_token_for(user)
    create(:access_token, :active, user: user)
  end

  test "#enable should promote a feed to enabled without any preview" do
    feed = create(:feed, :disabled,
      user: preview_user,
      access_token: access_token_for(preview_user),
      target_group: "tg",
      feed_profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" })

    assert feed.enable, feed.errors.full_messages.inspect
    assert_predicate feed.reload, :enabled?
  end

  test "#enable should fail when a required enabled-state field is missing" do
    feed = create(:feed, :disabled,
      user: preview_user,
      access_token: access_token_for(preview_user),
      target_group: "",
      feed_profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" })

    assert_not feed.enable
    assert feed.errors.of_kind?(:target_group, :blank)
    assert_predicate feed.reload, :disabled?
  end
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bin/rails test test/models/feed_test.rb -n "/enable should/"`
Expected: FAIL — the first still passes only if a preview happens to exist; the second fails because the current `enable` returns false for the missing preview, not (only) the missing target_group, and `:preview_required` is still wired. (Either way the suite is red until Step 3.)

- [ ] **Step 3: Remove the validator and its method; simplify `enable`**

In `app/models/feed.rb`:

Delete this validator line (currently line 62):
```ruby
  validate :enabling_requires_recent_preview, on: :enable
```

Replace the `enable` method (currently lines 162-168) with:
```ruby
  # Promote the feed to enabled, running the enabled-state validators. If
  # validation fails, the DB stays at the prior state, errors are added to the
  # feed, and the in-memory state is rolled back to its persisted value so
  # re-renders reflect DB truth.
  def enable
    self.state = :enabled
    return true if save

    self.state = state_was
    false
  end
```

Delete the `enabling_requires_recent_preview` method entirely (currently lines 287-300, including its leading comment block at 287-291).

Update the `ENABLE_PREVIEW_WINDOW` comment (currently lines 42-44) to drop the gate reference — leave just:
```ruby
  # How long a ready FeedPreview is reused before a fresh run is forced.
  PREVIEW_FRESHNESS_WINDOW = 60.minutes
```
(The rename is finished in Task 3; for now this task may keep the old name if Task 3 runs separately — but since they are one logical change, prefer doing the rename here and skipping Task 3's model edit. See Task 3.)

- [ ] **Step 4: Run the model tests to verify they pass**

Run: `bin/rails test test/models/feed_test.rb`
Expected: PASS (0 failures). If a `:preview_required` reference remains anywhere it will error — grep `git grep preview_required` and remove stragglers.

- [ ] **Step 5: Commit**

```bash
git add app/models/feed.rb test/models/feed_test.rb
git commit -m "Drop preview gate from feed enabling"
```

---

## Task 2: Remove `FeedPreview.fresh_ready` and its helper

**Files:**
- Modify: `app/models/feed_preview.rb`
- Test: `test/models/feed_preview_test.rb:107-130`
- Delete: `test/support/preview_helpers.rb`

- [ ] **Step 1: Confirm `fresh_ready` and the seed helper are now unused**

Run: `git grep -n "fresh_ready\|seed_ready_preview"`
Expected: matches only in `app/models/feed_preview.rb`, `test/models/feed_preview_test.rb`, and `test/support/preview_helpers.rb`. If `seed_ready_preview` appears in any other test (e.g. a controller/integration test), that test must be updated in Task 5 first — note it and proceed.

- [ ] **Step 2: Delete the `fresh_ready` tests**

In `test/models/feed_preview_test.rb`, delete both tests: `".fresh_ready should find a ready preview within the window"` and `".fresh_ready should ignore stale or non-ready previews"` (lines 107-130).

- [ ] **Step 3: Remove the method**

In `app/models/feed_preview.rb`, delete the `self.fresh_ready` method (lines 31-37).

- [ ] **Step 4: Delete the now-unused helper**

```bash
git rm test/support/preview_helpers.rb
```

- [ ] **Step 5: Run the preview model tests**

Run: `bin/rails test test/models/feed_preview_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/models/feed_preview.rb test/models/feed_preview_test.rb
git commit -m "Remove unused fresh_ready preview lookup"
```

---

## Task 3: Rename `ENABLE_PREVIEW_WINDOW` → `PREVIEW_FRESHNESS_WINDOW`

If Task 1 Step 3 already renamed the constant in `feed.rb`, this task covers the remaining references only.

**Files:**
- Modify: `app/models/feed.rb` (if not already), `app/controllers/feed_previews_controller.rb`, `app/jobs/prune_feed_previews_job.rb`
- Test: `test/controllers/feed_previews_controller_test.rb:165-184`

- [ ] **Step 1: Find every reference**

Run: `git grep -n "ENABLE_PREVIEW_WINDOW"`
Expected matches: `app/controllers/feed_previews_controller.rb:79`, `app/jobs/prune_feed_previews_job.rb:2`, `test/controllers/feed_previews_controller_test.rb:169`, and `app/models/feed.rb` if not yet renamed.

- [ ] **Step 2: Rename the constant and update prose**

In `app/models/feed.rb` (if still present) the constant is `PREVIEW_FRESHNESS_WINDOW` (done in Task 1).

In `app/controllers/feed_previews_controller.rb`, change `stale_ready?` (line 79):
```ruby
    preview.ready? && preview.ready_at.present? && preview.ready_at < Feed::PREVIEW_FRESHNESS_WINDOW.ago
```

In `app/jobs/prune_feed_previews_job.rb`, replace the comment (lines 1-2):
```ruby
# Removes stale preview rows. Ready previews are only reused within
# Feed::PREVIEW_FRESHNESS_WINDOW, so anything older than RETENTION is safe to drop.
```

In `test/controllers/feed_previews_controller_test.rb`, rename both tests and the constant: change "outside the enable window" → "outside the freshness window", "within the enable window" → "within the freshness window", and `Feed::ENABLE_PREVIEW_WINDOW` → `Feed::PREVIEW_FRESHNESS_WINDOW` (line 169).

- [ ] **Step 3: Verify no stragglers**

Run: `git grep -n "ENABLE_PREVIEW_WINDOW"`
Expected: no matches.

- [ ] **Step 4: Run affected tests**

Run: `bin/rails test test/controllers/feed_previews_controller_test.rb test/jobs/prune_feed_previews_job_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/feed_previews_controller.rb app/jobs/prune_feed_previews_job.rb test/controllers/feed_previews_controller_test.rb app/models/feed.rb
git commit -m "Rename preview window constant to its meaning"
```

---

## Task 4: Generalize `Feed#can_be_previewed?`

**Files:**
- Modify: `app/models/feed.rb:170-172`
- Test: `test/models/feed_test.rb` (add near the other `#can_be_*` tests)

- [ ] **Step 1: Write failing tests**

Add to `test/models/feed_test.rb`:
```ruby
  test "#can_be_previewed? should be true for a query-shaped profile with a query" do
    feed = build(:feed, feed_profile_key: "llm_web_search", params: { "query" => "ruby news" })

    assert feed.can_be_previewed?
  end

  test "#can_be_previewed? should be false when the source input is blank" do
    feed = build(:feed, feed_profile_key: "llm_web_search", params: { "query" => "" })

    assert_not feed.can_be_previewed?
  end
```
(Confirm `llm_web_search` is the `:query`-shaped profile key via `git grep -n "input_shape: :query" app/models/feed_profile.rb`; substitute the actual key if different.)

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/models/feed_test.rb -n "/can_be_previewed/"`
Expected: FAIL — the query case is false because `can_be_previewed?` checks `url.present?`.

- [ ] **Step 3: Generalize the method**

In `app/models/feed.rb`, replace `can_be_previewed?` (lines 170-172):
```ruby
  def can_be_previewed?
    source_input.present? && feed_profile_present?
  end
```

- [ ] **Step 4: Run to verify pass**

Run: `bin/rails test test/models/feed_test.rb -n "/can_be_previewed/"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/feed.rb test/models/feed_test.rb
git commit -m "Gate previewability on source input not url"
```

---

## Task 5: Make controller/integration tests reflect optional preview

**Files:**
- Test: `test/controllers/feeds_controller_test.rb`
- Test: `test/integration/smart_feed_creation_rss_test.rb`, `test/integration/smart_feed_creation_ai_website_test.rb` (only if red)

- [ ] **Step 1: Replace the "no preview blocks enable" test**

In `test/controllers/feeds_controller_test.rb`, the test `"#create should persist as draft and re-render with errors when no recent preview exists"` (lines 119-139) asserts a now-removed behavior. Replace its body so it asserts the feed is **enabled** without a preview:
```ruby
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
```

- [ ] **Step 2: Drop now-unnecessary preview seeding**

In the same file, remove the `create(:feed_preview, :completed, ...)` seeding lines that existed only to pass the gate (the block at lines 80-81 in `"#create should ... enable ..."`, and lines 154-155 in `"#create should persist as draft and re-render when enable-validation fails on a missing field"`). The latter test still asserts a `target_group` failure, which stands on its own. Update the stale comment at the `#update` test (lines ~602-604) that mentions `enabling_requires_recent_preview` to remove the gate reference.

- [ ] **Step 3: Run the controller tests**

Run: `bin/rails test test/controllers/feeds_controller_test.rb`
Expected: PASS.

- [ ] **Step 4: Run the full integration suite; fix only what's red**

Run: `bin/rails test test/integration`
Expected: PASS. The smart-feed-creation integration tests POST a preview then enable; with the gate gone they should still pass (the preview is simply no longer required). If any now fail because they asserted the gate, adjust that single assertion to the new optional behavior. Do not rewrite passing tests.

- [ ] **Step 5: Run the full suite + RuboCop**

Run: `bin/rails test && bin/rubocop -f github`
Expected: PASS / no offenses. This closes the backend half.

- [ ] **Step 6: Commit**

```bash
git add test/
git commit -m "Update specs for optional feed preview"
```

---

## Task 6: Replace the auto-preview frame with the Preview button + modal

**Files:**
- Modify: `app/views/feeds/_form_expanded.html.erb:65-76`
- Test: `test/controllers/feeds_controller_test.rb` (request-level structure)

- [ ] **Step 1: Write failing request tests for the new structure**

Add to `test/controllers/feeds_controller_test.rb`:
```ruby
  test "#new should render a manual preview button and no auto-loading frame" do
    sign_in_as(user)
    access_token

    get new_feed_path(url: "http://example.com/feed.xml")

    assert_response :success
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
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/controllers/feeds_controller_test.rb -n "/manual preview button/"`
Expected: FAIL — no `preview.open` element; the lazy frame still present in `new`.

- [ ] **Step 3: Replace the preview block in `_form_expanded.html.erb`**

Replace the whole `<% unless edit_mode %> … <% end %>` preview block (lines 65-76) with:

```erb
      <%
        preview_shapes =
          if multi_candidate
            candidates.to_h { |c| [c["profile_key"], FeedProfile[c["profile_key"]]&.dig(:input_shape).to_s] }
          else
            { feed.feed_profile_key => feed.source_input_shape }
          end
      %>
      <div class="mt-2"
           data-key="form.preview"
           data-controller="preview-button"
           data-preview-button-endpoint-value="<%= feed_preview_path %>"
           data-preview-button-source-value="<%= feed.source_input %>"
           data-preview-button-shapes-value="<%= preview_shapes.to_json %>"
           data-preview-button-modal-id-value="feed-preview-modal">
        <button type="button"
                <%= "disabled" unless feed.can_be_previewed? %>
                class="inline-flex items-center gap-1 rounded-md border border-slate-200 bg-white px-4 py-2 text-base font-semibold text-slate-700 shadow-sm transition hover:bg-slate-50 disabled:opacity-50 disabled:cursor-not-allowed"
                data-preview-button-target="button"
                data-action="click->preview-button#open"
                data-key="preview.open">
          See what we'd post
        </button>

        <%= render ModalComponent.new(title: "Feed preview", modal_id: "feed-preview-modal") do %>
          <%= turbo_frame_tag "feed-preview", data: { preview_button_target: "frame" } do %>
            <p class="text-slate-500">Pick this feed's source above, then we'll build a preview here.</p>
          <% end %>
        <% end %>
      </div>
```

Notes for the implementer:
- The `data-controller="preview-button"` element wraps both the trigger and the modal so the controller's `frame` target (inside the modal) is in scope.
- The modal (and thus its `feed-preview` frame) renders inside the `form_with` block, so `_credential_gate`'s submit posts the outer form. No other `<form>` may appear inside the preview partials (handled in Task 8).
- `feed.source_input` and `feed.source_input_shape` already exist on the model.

- [ ] **Step 4: Run to verify pass (after Task 7 the JS works; structure passes now)**

Run: `bin/rails test test/controllers/feeds_controller_test.rb -n "/manual preview button/"`
Expected: PASS (server-rendered structure only; clicking is wired in Task 7).

- [ ] **Step 5: Commit**

```bash
git add app/views/feeds/_form_expanded.html.erb test/controllers/feeds_controller_test.rb
git commit -m "Render manual preview button and modal host"
```

---

## Task 7: Add the `preview_button` Stimulus controller

**Files:**
- Create: `app/javascript/controllers/preview_button_controller.js`
- Modify: `app/javascript/controllers/modal_controller.js`

- [ ] **Step 1: Add a generic `modal:hide` dispatch to the modal controller**

In `app/javascript/controllers/modal_controller.js`, inside `close(event)`, after the element is hidden (after the `document.body.style.paddingRight = ''` line, before the focus-restore block), add:
```javascript
    this.element.dispatchEvent(new CustomEvent('modal:hide', { bubbles: true }))
```
This is a generic hook (not preview-specific) other controllers can also use.

- [ ] **Step 2: Create the controller**

Create `app/javascript/controllers/preview_button_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"

// Drives the manual feed preview:
// - keeps the button enabled only when a profile is selected and a source is present
// - on click, points the modal's feed-preview frame at the preview endpoint for
//   the currently selected profile + source, then opens the modal
// - on modal close, clears the frame so the polling host unmounts (stops polling)
export default class extends Controller {
  static targets = ["button", "frame"]
  static values = {
    endpoint: String,
    source: String,
    shapes: Object,
    modalId: String
  }

  connect() {
    this._onHide = this._clearFrame.bind(this)
    this._modal = document.getElementById(this.modalIdValue)
    this._modal?.addEventListener("modal:hide", this._onHide)

    this._onFormChange = this.refreshAvailability.bind(this)
    this.element.addEventListener("change", this._onFormChange)
    this.refreshAvailability()
  }

  disconnect() {
    this._modal?.removeEventListener("modal:hide", this._onHide)
    this.element.removeEventListener("change", this._onFormChange)
  }

  open(event) {
    event?.preventDefault()
    const profileKey = this._selectedProfileKey()
    if (!profileKey || !this.sourceValue || !this.hasFrameTarget) return

    const shape = this.shapesValue[profileKey]
    if (!shape) return

    const url = new URL(this.endpointValue, window.location.origin)
    url.searchParams.set("profile_key", profileKey)
    url.searchParams.set(`params[${shape}]`, this.sourceValue)
    this.frameTarget.setAttribute("src", url.toString())

    this._modal?.dispatchEvent(new CustomEvent("modal:show"))
  }

  refreshAvailability() {
    if (!this.hasButtonTarget) return
    const ready = !!this._selectedProfileKey() && !!this.sourceValue
    this.buttonTarget.disabled = !ready
  }

  _selectedProfileKey() {
    const checked = this.element.querySelector("input[name='feed[feed_profile_key]']:checked")
    if (checked) return checked.value
    const hidden = this.element.querySelector("input[type=hidden][name='feed[feed_profile_key]']")
    return hidden ? hidden.value : null
  }

  _clearFrame() {
    if (this.hasFrameTarget) this.frameTarget.removeAttribute("src")
  }
}
```

Notes:
- `_clearFrame` removing `src` empties the frame on close, unmounting the polling host so `polling_controller#disconnect` runs and stops polling. Reopening re-points `src` at `show`, which reuses the now-ready row.
- The controller reads the checked radio (multi-candidate) or the hidden field (single), so candidate switching needs no event wiring.

- [ ] **Step 3: Verify the controller auto-registers**

Run: `git grep -n "eagerLoadControllers\|application.register\|import.*Controller" app/javascript/controllers/index.js`
Expected: controllers are auto-loaded (stimulus-loading `eagerLoadControllersFrom`) — no manual registration needed. If `index.js` registers controllers explicitly, add `preview-button` there following the existing pattern.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/preview_button_controller.js app/javascript/controllers/modal_controller.js
git commit -m "Add preview-button controller and modal hide hook"
```

---

## Task 8: Fix refresh wiring and remove the nested form

**Files:**
- Modify: `app/javascript/controllers/preview_controller.js`
- Modify: `app/views/feed_previews/_failed.html.erb`

- [ ] **Step 1: Slim `preview_controller` to refresh-via-`closest`**

Replace the entire contents of `app/javascript/controllers/preview_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"

// Forces a fresh preview run from inside the feed-preview frame (the "Refresh
// preview" / "Try again" buttons). POSTs to the preview endpoint (which busts
// the cached run) and reloads the enclosing turbo-frame so the polling host
// remounts and resumes polling.
export default class extends Controller {
  static values = { refreshUrl: String }

  async refresh(event) {
    event?.preventDefault()
    if (!this.hasRefreshUrlValue) return

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    await fetch(this.refreshUrlValue, {
      method: "POST",
      headers: {
        Accept: "text/html",
        "X-CSRF-Token": csrfToken,
        "X-Requested-With": "XMLHttpRequest"
      },
      credentials: "same-origin"
    })

    const frame = this.element.closest("turbo-frame#feed-preview")
    if (frame && typeof frame.reload === "function") {
      frame.reload()
    } else if (frame) {
      const src = frame.getAttribute("src")
      frame.setAttribute("src", "")
      frame.setAttribute("src", src)
    }
  }
}
```
(`_ready.html.erb` already mounts `data-controller="preview"`, sets `data-preview-refresh-url-value`, and binds `click->preview#refresh` — no change needed there. It no longer needs a `frame` target.)

- [ ] **Step 2: Convert `_failed` "Try again" to a JS button (no nested form)**

Replace `app/views/feed_previews/_failed.html.erb`:
```erb
<%# locals: (preview:) %>
<div class="rounded-lg border border-red-200 bg-red-100 px-4 py-3 text-red-800 space-y-3"
     role="alert"
     data-key="preview.failed"
     data-controller="preview"
     data-preview-refresh-url-value="<%= feed_preview_path(profile_key: preview.feed_profile_key, "params" => preview.params) %>"
     data-preview-done>
  <div class="space-y-1">
    <p class="font-semibold text-slate-800">We couldn't build a preview.</p>
    <p class="text-slate-600">Something went wrong fetching this source. Double-check it and give it another go.</p>
  </div>
  <button type="button"
          class="inline-flex items-center gap-1 rounded-md border border-slate-200 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 shadow-sm transition hover:bg-slate-50"
          data-action="click->preview#refresh"
          data-key="preview.try-again">
    Try again
  </button>
</div>
```

- [ ] **Step 3: Verify no `button_to`/`form_with`/`form_tag` remains in the preview partials**

Run: `git grep -n "button_to\|form_with\|form_tag\|<form" app/views/feed_previews`
Expected: no matches (only `_credential_gate`'s bare `<button type="submit">` remains, which posts the outer feed form).

- [ ] **Step 4: Run the preview request/integration tests**

Run: `bin/rails test test/integration/credential_gate_test.rb test/integration/smart_feed_creation_rss_test.rb`
Expected: PASS (these exercise the `show`/`create` endpoints and partials).

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/preview_controller.js app/views/feed_previews/_failed.html.erb
git commit -m "Fix preview refresh and drop nested form"
```

---

## Task 9: Remove the dead candidate-changed dispatch

**Files:**
- Modify: `app/views/feeds/_candidate_chooser.html.erb`
- Delete: `app/javascript/controllers/candidate_chooser_controller.js`

- [ ] **Step 1: Confirm the controller's only job was the dispatch**

Run: `git grep -n "candidate-chooser\|candidate_chooser\|feed:candidate-changed"`
Expected: references only in `_candidate_chooser.html.erb` and `candidate_chooser_controller.js` (the `preview_controller` listener was removed in Task 8). If anything else listens for `feed:candidate-changed`, stop and reassess.

- [ ] **Step 2: Strip the chooser wiring**

In `app/views/feeds/_candidate_chooser.html.erb`:
- On the wrapping `<div>` (lines 4-6), remove `data-controller="candidate-chooser"`.
- On the radio `<input>` (lines 18-24), remove `data-action="change->candidate-chooser#switch"` and `data-candidate-chooser-target="option"`.

The radios keep `name="feed[feed_profile_key]"`, so selection still submits and the `preview_button` controller reads the checked value at click time. (The `change` event still bubbles to `preview-button#refreshAvailability` via the form-level listener.)

- [ ] **Step 3: Delete the controller**

```bash
git rm app/javascript/controllers/candidate_chooser_controller.js
```

- [ ] **Step 4: Verify nothing references it**

Run: `git grep -n "candidate-chooser\|candidate_chooser"`
Expected: no matches.

- [ ] **Step 5: Commit**

```bash
git add app/views/feeds/_candidate_chooser.html.erb
git commit -m "Remove dead candidate-changed dispatch"
```

---

## Task 10: Update AI-cost copy

**Files:**
- Modify: `app/views/feeds/_form_expanded.html.erb:24-29`
- Modify: `app/views/feed_previews/_ready.html.erb` (refresh button copy)

- [ ] **Step 1: Drop the auto-preview implication from the cost notice**

In `app/views/feeds/_form_expanded.html.erb`, change the notice text (line 27-28) from:
```
          AI fetches (including this preview) cost tokens. You'll see your spend on the feed page.
```
to:
```
          AI fetches cost tokens. Previewing or refreshing a preview spends some too — you'll see your spend on the feed page.
```

- [ ] **Step 2: Keep refresh copy honest (optional)**

The `_ready.html.erb` "Refresh preview" button label is fine; no change required. (Listed for completeness — skip if no copy change is warranted.)

- [ ] **Step 3: Run the full suite + RuboCop**

Run: `bin/rails test && bin/rubocop -f github`
Expected: PASS / no offenses.

- [ ] **Step 4: Commit**

```bash
git add app/views/feeds/_form_expanded.html.erb
git commit -m "Clarify AI token cost copy for manual preview"
```

---

## Task 11: Browser verification

The test suite has **no JS/system coverage**; it did not catch the earlier polling busy-loop or the broken refresh. Verify the interactive behavior in a real browser using the `verify` / `playwright-cli` flow. Do not claim completion without observing each item.

- [ ] **Step 1: Start the app and sign in**

Use the project's run flow (see the `run` skill / `bin/dev`). Sign in and reach a new-feed form by entering a source (e.g. an RSS URL) so `_form_expanded` renders.

- [ ] **Step 2: Verify each behavior**

- [ ] Button is disabled when no profile/source; enabled once a profile is selected and source present.
- [ ] Click "See what we'd post" → modal opens, shows the processing state, polls, then renders the preview (`_ready`).
- [ ] "Refresh preview" forces a fresh run and the pane visibly returns to processing then ready.
- [ ] Close the modal while processing → polling stops (watch the network panel: no further requests to `/feed_preview`). Reopen → shows the ready result.
- [ ] Multi-candidate: switch the selected candidate, open preview → the preview reflects the switched profile (correct param key).
- [ ] AI profile with no active LLM credential → modal shows the credential gate; "Add AI credentials" saves the feed as a draft and proceeds to credential setup.
- [ ] On the **edit** form: the button renders and previews the persisted profile + params.
- [ ] Check "Enable feed" and save **without** previewing → the feed is enabled (no preview required).

- [ ] **Step 3: Record the result**

Note any failures with the observed behavior. If all pass, the branch is ready for PR/review.

---

## Self-Review Notes

- **Spec coverage:** gate removal (Tasks 1-3, 5), `can_be_previewed?` generalization (Task 4), button in new+edit (Task 6), dynamic availability + per-profile param-key contract (Tasks 6-7), modal hosting + single host (Task 6), refresh-via-`closest` + no nested form (Task 8), stop-polling-on-close (Task 7), dead-dispatch deletion (Task 9), UX copy (Task 10), browser verification (Task 11). All spec sections map to a task.
- **Reference sweep:** Tasks 1-3/5 each end with a `git grep` for the removed name (`preview_required`, `fresh_ready`, `ENABLE_PREVIEW_WINDOW`, `seed_ready_preview`) so the old invariant can't survive.
- **Type/name consistency:** controller value names (`endpoint`, `source`, `shapes`, `modalId`) match the `data-preview-button-*-value` attributes in Task 6; the frame id `feed-preview` is identical across the view, `show.html.erb`, and the `closest("turbo-frame#feed-preview")` lookups.
</content>
