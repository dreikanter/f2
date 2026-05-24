# Unify Feed Preview Stack — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the two parallel feed-preview subsystems into one persisted stack: a single `FeedPreviewsController`, a generalized `FeedPreview` model, one `FeedPreviewJob`, the existing `FeedPreviewWorkflow`, with the enable gate backed by a DB lookup instead of an HMAC token.

**Architecture:** Persist every preview as a `FeedPreview` row keyed by `(user, feed_profile_key, params_digest)`. The controller builds a validated transient `Feed` from feed data, upserts a row, and enqueues `FeedPreviewJob`, which runs `FeedPreviewWorkflow` (load→process→normalize in memory) and finalizes the row under a per-run token. `Feed#enabling_requires_recent_preview` becomes a freshness query against that row. `FeedRefreshWorkflow` is untouched.

**Tech Stack:** Rails (edge), PostgreSQL, SolidQueue, Turbo/Stimulus, Minitest + FactoryBot.

**Reference:** [`spec.md`](./spec.md) in this directory.

**Delivery status (3 PRs):**
- **PR1 (#440, merged):** AI loader prompt rendering via `{{input}}` + removal of the
  `llm_handle_search` profile and `:handle` input_shape. This covered Phase G1 (and
  more). Input shapes are now just `:url` / `:query`. `Feed#source_input_shape` was
  *removed* in PR1 (the gsub no longer needs it) — Phase E2 below re-adds it for the
  form pane.
- **PR2 (this branch):** Phases A, B, C, D, E, F, G2, I — the consolidation core.
- **PR3 (follow-up):** Phase H — retention sweeper.

---

## File Structure

**Modify**
- `db/migrate/<ts>_generalize_feed_previews.rb` — new migration (params, params_digest, ready_at, run_id, unique index, drop url)
- `app/models/feed_preview.rb` — drop url, add params/params_digest/ready_at/run_id, digest helper, finder
- `app/models/feed.rb` — enable gate → DB query; delete `preview_token` attr
- `app/services/feed_preview_workflow.rb` — build feed from params, set ready_at, run-token-guarded transitions
- `app/jobs/feed_preview_job.rb` — replaced by the DB-backed job (renamed from admin)
- `app/controllers/feed_previews_controller.rb` — unified create/show/destroy, user-scoped, credential gate
- `app/controllers/feeds_controller.rb` — remove `preview_token` plumbing
- `app/services/loader/llm_loader.rb` — generalize prompt rendering to input_shape
- `app/views/feeds/_form_expanded.html.erb` — repoint preview pane, fix url-only param
- `app/views/feeds/show.html.erb` — drop the Preview button
- `config/routes.rb` — drop nested live_preview, keep `resources :feed_previews`
- `config/recurring.yml` — add preview prune job
- `test/factories/feed_previews.rb` — params instead of url

**Create**
- `app/jobs/prune_feed_previews_job.rb` — retention sweeper
- `test/support/preview_helpers.rb` (or add to test_helper) — `seed_ready_preview` for enable-gate tests

**Delete**
- `app/controllers/feeds/previews_controller.rb`
- `app/services/feed_preview_service.rb`
- `app/services/preview_token.rb`
- `app/jobs/admin_feed_preview_job.rb` (its logic moves into `feed_preview_job.rb`)
- old `app/jobs/feed_preview_job.rb` cache logic (overwritten)
- `app/views/feed_previews/*` and/or `app/views/feeds/previews/*` duplicates (consolidate to one set)
- `test/services/preview_token_test.rb`, `test/services/feed_preview_service_test.rb`
- `test/controllers/feeds/previews_controller_test.rb` (folded into unified suite)

---

## Phase A — Generalize the `FeedPreview` model

### Task A1: Migration — generalize columns

**Files:**
- Create: `db/migrate/<timestamp>_generalize_feed_previews.rb`

- [ ] **Step 1: Generate the migration**

Run: `bin/rails g migration GeneralizeFeedPreviews`

- [ ] **Step 2: Write the migration body**

```ruby
class GeneralizeFeedPreviews < ActiveRecord::Migration[8.1]
  def up
    add_column :feed_previews, :params, :jsonb, null: false, default: {}
    add_column :feed_previews, :params_digest, :string
    add_column :feed_previews, :ready_at, :datetime
    add_column :feed_previews, :run_id, :string

    # Existing rows are ephemeral previews; discard rather than backfill.
    execute "DELETE FROM feed_previews"

    change_column_null :feed_previews, :params_digest, false
    add_index :feed_previews,
              [:user_id, :feed_profile_key, :params_digest],
              unique: true,
              name: "index_feed_previews_on_owner_profile_digest"

    remove_column :feed_previews, :url, :string, null: false
  end

  def down
    add_column :feed_previews, :url, :string
    execute "DELETE FROM feed_previews"
    change_column_null :feed_previews, :url, false

    remove_index :feed_previews, name: "index_feed_previews_on_owner_profile_digest"
    remove_column :feed_previews, :run_id
    remove_column :feed_previews, :ready_at
    remove_column :feed_previews, :params_digest
    remove_column :feed_previews, :params
  end
end
```

- [ ] **Step 3: Run the migration up**

Run: `bin/rails db:migrate`
Expected: `feed_previews` gains params/params_digest/ready_at/run_id, loses url; schema.rb updated.

- [ ] **Step 4: Verify it reverses**

Run: `bin/rails db:rollback && bin/rails db:migrate`
Expected: both directions succeed with no errors.

- [ ] **Step 5: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "Generalize feed_previews: params/params_digest/ready_at/run_id"
```

### Task A2: Model — digest, columns, finder

**Files:**
- Modify: `app/models/feed_preview.rb`
- Test: `test/models/feed_preview_test.rb`

- [ ] **Step 1: Write failing tests for the digest + finder**

```ruby
test "#params_digest should be stable regardless of key order" do
  a = build(:feed_preview, params: { "url" => "https://x.test", "extra" => "1" })
  b = build(:feed_preview, params: { "extra" => "1", "url" => "https://x.test" })
  assert_equal a.params_digest, b.params_digest
end

test ".fresh_ready should find a ready preview within the window" do
  user = create(:user)
  preview = create(:feed_preview, :completed, user: user,
                   feed_profile_key: "rss", params: { "url" => "https://x.test" })
  preview.update!(ready_at: 1.minute.ago)

  found = FeedPreview.fresh_ready(
    user_id: user.id, feed_profile_key: "rss",
    params: { "url" => "https://x.test" }, within: 60.minutes
  )
  assert_equal preview, found
end

test ".fresh_ready should ignore stale or non-ready previews" do
  user = create(:user)
  create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
         params: { "url" => "https://x.test" }, ready_at: 2.hours.ago)

  assert_nil FeedPreview.fresh_ready(
    user_id: user.id, feed_profile_key: "rss",
    params: { "url" => "https://x.test" }, within: 60.minutes
  )
end
```

- [ ] **Step 2: Run to confirm failure**

Run: `bin/rails test test/models/feed_preview_test.rb -n "/params_digest|fresh_ready/"`
Expected: FAIL (`params_digest` / `fresh_ready` undefined).

- [ ] **Step 3: Implement model changes**

Replace url-centric code in `app/models/feed_preview.rb`:

```ruby
class FeedPreview < ApplicationRecord
  PREVIEW_POSTS_LIMIT = 10

  belongs_to :user
  belongs_to :feed, optional: true

  enum :status, { pending: 0, processing: 1, ready: 2, failed: 3 }

  validates :feed_profile_key, presence: true
  validates :feed_profile_key, inclusion: { in: ->(_) { FeedProfile.all } }, if: -> { feed_profile_key.present? }

  before_validation :assign_params_digest

  # Canonical digest of the source params. Must match Feed#params_digest so the
  # enable gate (reader) and the preview (writer) agree on identity.
  def self.digest_for(params)
    canonical = (params || {}).deep_stringify_keys.sort.to_h.to_json
    Digest::SHA256.hexdigest(canonical)
  end

  def self.fresh_ready(user_id:, feed_profile_key:, params:, within:)
    where(user_id: user_id, feed_profile_key: feed_profile_key, params_digest: digest_for(params))
      .ready
      .where(ready_at: within.ago..)
      .order(ready_at: :desc)
      .first
  end

  def params_digest
    self.class.digest_for(params)
  end

  def posts_data
    (data.present? && ready? && data["posts"]) || []
  end

  def posts_count
    posts_data.size
  end

  private

  def assign_params_digest
    self[:params_digest] = self.class.digest_for(params)
  end
end
```

- [ ] **Step 4: Update the factory**

Replace `sequence(:url) { ... }` in `test/factories/feed_previews.rb` with:

```ruby
    feed_profile_key { "rss" }
    sequence(:params) { |n| { "url" => "https://example#{n}.com/feed.xml" } }
    status { :pending }
    data { nil }
```

Remove the `url` attribute and any url references in traits.

- [ ] **Step 5: Run tests**

Run: `bin/rails test test/models/feed_preview_test.rb`
Expected: PASS (update/remove any remaining url-based assertions in that file).

- [ ] **Step 6: RuboCop + commit**

```bash
bin/rubocop -f github app/models/feed_preview.rb test/factories/feed_previews.rb test/models/feed_preview_test.rb
git add app/models/feed_preview.rb test/factories/feed_previews.rb test/models/feed_preview_test.rb
git commit -m "FeedPreview: params-based identity, fresh_ready finder"
```

---

## Phase B — Workflow on a transient feed, run-token guarded

### Task B1: Build the transient feed from params; guard transitions by run_id

**Files:**
- Modify: `app/services/feed_preview_workflow.rb`
- Test: `test/services/feed_preview_workflow_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
test "#execute should mark the preview ready with normalized posts and ready_at" do
  preview = create(:feed_preview, feed_profile_key: "rss",
                   params: { "url" => "https://example.com/feed.xml" }, run_id: "run-1")
  stub_rss_loader_returning_one_item

  FeedPreviewWorkflow.new(preview, run_id: "run-1").execute

  preview.reload
  assert preview.ready?
  assert preview.ready_at.present?
  assert_equal 1, preview.posts_count
end

test "#execute should not finalize when the run_id is stale" do
  preview = create(:feed_preview, feed_profile_key: "rss",
                   params: { "url" => "https://example.com/feed.xml" }, run_id: "run-2")
  stub_rss_loader_returning_one_item

  FeedPreviewWorkflow.new(preview, run_id: "run-1").execute # superseded run

  preview.reload
  refute preview.ready?
end
```

(Use the file's existing loader-stubbing approach; `stub_rss_loader_returning_one_item` is shorthand for whatever the current test already does to fake `loader.load`.)

- [ ] **Step 2: Run to confirm failure**

Run: `bin/rails test test/services/feed_preview_workflow_test.rb -n "/ready_at|stale/"`
Expected: FAIL (constructor arity / run-guard not implemented).

- [ ] **Step 3: Implement workflow changes**

In `app/services/feed_preview_workflow.rb`:

```ruby
  def initialize(feed_preview, run_id: nil)
    @feed_preview = feed_preview
    @run_id = run_id || feed_preview.run_id
  end

  private

  attr_reader :run_id

  # Conditional update: only the current run may transition the row. A stale
  # run (superseded by a newer enqueue that rewrote run_id) updates 0 rows.
  def transition!(attrs)
    scope = FeedPreview.where(id: feed_preview.id, run_id: run_id)
    updated = scope.update_all(attrs.merge(updated_at: Time.current))
    feed_preview.reload if updated.positive?
    updated.positive?
  end

  def on_error(error)
    record_error_stats(error, current_step: current_step)
    logger.error "FeedPreviewWorkflow error at #{current_step}: #{error.message}"
    transition!(status: FeedPreview.statuses[:failed])
  end

  def initialize_workflow(_input)
    record_started_at
    transition!(status: FeedPreview.statuses[:processing])

    Feed.new(
      params: feed_preview.params,
      feed_profile_key: feed_preview.feed_profile_key,
      user: feed_preview.user
    )
  end
```

And in `finalize_workflow`, replace the `feed_preview.update!(...)` with:

```ruby
  def finalize_workflow(posts)
    record_completed_at
    transition!(
      status: FeedPreview.statuses[:ready],
      ready_at: Time.current,
      data: { posts: posts, stats: stats }
    )
    posts
  end
```

Note: the transient `Feed` is built from `params` (not `url`), so query profiles flow through; `LlmClient.for(feed)` resolves the user's credential for AI profiles.

- [ ] **Step 4: Run tests**

Run: `bin/rails test test/services/feed_preview_workflow_test.rb`
Expected: PASS.

- [ ] **Step 5: RuboCop + commit**

```bash
bin/rubocop -f github app/services/feed_preview_workflow.rb test/services/feed_preview_workflow_test.rb
git add app/services/feed_preview_workflow.rb test/services/feed_preview_workflow_test.rb
git commit -m "FeedPreviewWorkflow: build from params, run-guarded transitions, ready_at"
```

---

## Phase C — One job named `FeedPreviewJob`

### Task C1: Replace the cache job with the DB-backed job

**Files:**
- Modify: `app/jobs/feed_preview_job.rb` (overwrite with admin job's logic)
- Delete: `app/jobs/admin_feed_preview_job.rb`
- Test: `test/jobs/feed_preview_job_test.rb` (overwrite), delete `test/jobs/admin_feed_preview_job_test.rb`

- [ ] **Step 1: Overwrite `app/jobs/feed_preview_job.rb`**

```ruby
# Runs FeedPreviewWorkflow for a persisted FeedPreview, under its current run_id.
class FeedPreviewJob < ApplicationJob
  queue_as :default

  # @param feed_preview_id [String] UUID of the FeedPreview
  # @param run_id [String] the run token captured when this job was enqueued
  def perform(feed_preview_id, run_id)
    feed_preview = FeedPreview.find_by(id: feed_preview_id)
    return unless feed_preview

    FeedPreviewWorkflow.new(feed_preview, run_id: run_id).execute
  rescue LlmClient::CredentialMissing => e
    # AI profile previewed without an active credential. The workflow already
    # marked the preview failed; this is a user-state condition, not a crash.
    Rails.logger.info "FeedPreviewJob: no AI credential for preview #{feed_preview_id}: #{e.message}"
  rescue => e
    Rails.logger.error "FeedPreviewJob failed for preview #{feed_preview_id}: #{e.message}"
    raise
  end
end
```

- [ ] **Step 2: Delete the admin job and its test**

```bash
git rm app/jobs/admin_feed_preview_job.rb test/jobs/admin_feed_preview_job_test.rb
```

- [ ] **Step 3: Overwrite `test/jobs/feed_preview_job_test.rb`**

```ruby
require "test_helper"

class FeedPreviewJobTest < ActiveJob::TestCase
  test "#perform should run the workflow and finalize the preview" do
    preview = create(:feed_preview, feed_profile_key: "rss",
                     params: { "url" => "https://example.com/feed.xml" }, run_id: "run-1")

    workflow = Minitest::Mock.new
    workflow.expect(:execute, nil)

    FeedPreviewWorkflow.stub(:new, ->(p, run_id:) { assert_equal preview, p; assert_equal "run-1", run_id; workflow }) do
      FeedPreviewJob.perform_now(preview.id, "run-1")
    end

    workflow.verify
  end

  test "#perform should no-op for a missing preview" do
    assert_nothing_raised { FeedPreviewJob.perform_now("00000000-0000-0000-0000-000000000000", "run-x") }
  end

  test "#perform should swallow CredentialMissing" do
    preview = create(:feed_preview, feed_profile_key: "llm_website_extractor",
                     params: { "url" => "https://example.com" }, run_id: "run-1")

    FeedPreviewWorkflow.stub(:new, ->(*, **) { raise LlmClient::CredentialMissing, "no credential" }) do
      assert_nothing_raised { FeedPreviewJob.perform_now(preview.id, "run-1") }
    end
  end
end
```

- [ ] **Step 4: Run tests**

Run: `bin/rails test test/jobs/feed_preview_job_test.rb`
Expected: PASS.

- [ ] **Step 5: RuboCop + commit**

```bash
bin/rubocop -f github app/jobs/feed_preview_job.rb test/jobs/feed_preview_job_test.rb
git add -A app/jobs test/jobs
git commit -m "Replace cache+admin preview jobs with one DB-backed FeedPreviewJob"
```

---

## Phase D — Unified `FeedPreviewsController` + routes

### Task D1: Rewrite the controller (user-scoped, credential gate, blank source)

**Files:**
- Modify: `app/controllers/feed_previews_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/feed_previews_controller_test.rb` (rewrite)

- [ ] **Step 1: Update routes**

In `config/routes.rb`: change the legacy line to include `:destroy` and remove the nested live_preview route.

```ruby
  resources :feed_previews, only: [:create, :show, :destroy], path: "previews"
```

Delete this line from the `resources :feeds` block:

```ruby
    resource :preview, only: [:show, :create, :destroy], controller: "feeds/previews", as: :live_preview
```

- [ ] **Step 2: Write failing controller tests**

```ruby
require "test_helper"

class FeedPreviewsControllerTest < ActionDispatch::IntegrationTest
  def user = @user ||= create(:user)

  test "#create should build a pending preview and enqueue the job" do
    sign_in_as(user)
    assert_difference("FeedPreview.count", 1) do
      assert_enqueued_with(job: FeedPreviewJob) do
        post feed_previews_path, params: { profile_key: "rss", params: { url: "https://example.com/feed.xml" } }
      end
    end
    preview = FeedPreview.last
    assert_equal user, preview.user
    assert preview.run_id.present?
  end

  test "#create should reuse the row for the same source (upsert)" do
    sign_in_as(user)
    create(:feed_preview, user: user, feed_profile_key: "rss", params: { "url" => "https://example.com/feed.xml" })
    assert_no_difference("FeedPreview.count") do
      post feed_previews_path, params: { profile_key: "rss", params: { url: "https://example.com/feed.xml" } }
    end
  end

  test "#create should clear the pane when the source input is blank" do
    sign_in_as(user)
    assert_no_difference("FeedPreview.count") do
      post feed_previews_path, params: { profile_key: "rss", params: { url: "" } }, as: :turbo_stream
    end
    assert_response :success
  end

  test "#show should not expose another user's preview" do
    sign_in_as(user)
    other = create(:feed_preview, :completed, user: create(:user))
    get feed_preview_path(other)
    assert_response :not_found
  end
end
```

- [ ] **Step 3: Run to confirm failure**

Run: `bin/rails test test/controllers/feed_previews_controller_test.rb`
Expected: FAIL.

- [ ] **Step 4: Rewrite the controller**

```ruby
class FeedPreviewsController < ApplicationController
  before_action :require_authentication

  def create
    if source_blank?
      return render_cleared
    end
    if needs_credential_gate?
      return render_credential_gate
    end

    preview = previews.find_or_initialize_by(feed_profile_key: profile_key, params_digest: FeedPreview.digest_for(preview_params))
    preview.assign_attributes(params: preview_params, status: :pending, data: nil, run_id: SecureRandom.uuid)
    preview.save!

    FeedPreviewJob.perform_later(preview.id, preview.run_id)
    render_state(preview)
  end

  def show
    @feed_preview = previews.find(params[:id])
    render_state(@feed_preview)
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { head :not_found }
      format.turbo_stream { head :not_found }
    end
  end

  def destroy
    previews.where(id: params[:id]).destroy_all
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("feed-preview", "") }
      format.html { head :no_content }
    end
  end

  private

  def previews
    Current.user.feed_previews
  end

  def profile_key
    @profile_key ||= params[:profile_key].to_s
  end

  def preview_params
    @preview_params ||= begin
      raw = params[:params]
      hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : (raw || {})
      hash.deep_stringify_keys
    end
  end

  def source_blank?
    shape = FeedProfile[profile_key]&.dig(:input_shape)
    key = shape ? shape.to_s : "url"
    preview_params[key].to_s.strip.blank?
  end

  def needs_credential_gate?
    return false unless FeedProfile.exists?(profile_key)
    return false unless FeedProfile.depends_on_ai?(profile_key)

    !Current.user.llm_credentials.active.exists?
  end

  def render_state(preview)
    respond_to do |format|
      format.html
      format.turbo_stream { render turbo_stream: preview_streams(preview) }
    end
  end

  def render_cleared
    respond_to do |format|
      format.html { head :no_content }
      format.turbo_stream { render turbo_stream: turbo_stream.update("feed-preview", "") }
    end
  end

  def render_credential_gate
    render turbo_stream: turbo_stream.update(
      "feed-preview",
      partial: "feed_previews/credential_gate",
      locals: { profile_key: profile_key }
    )
  end

  def preview_streams(preview)
    partial =
      case preview.status
      when "ready" then "feed_previews/ready"
      when "failed" then "feed_previews/failed"
      else "feed_previews/processing"
      end
    [turbo_stream.update("feed-preview", partial: partial, locals: { preview: preview })]
  end
end
```

- [ ] **Step 5: Run tests**

Run: `bin/rails test test/controllers/feed_previews_controller_test.rb`
Expected: PASS (create the view partials in Phase E if the turbo_stream renders fail — temporarily the html format suffices for these assertions; partials land in E).

- [ ] **Step 6: RuboCop + commit**

```bash
bin/rubocop -f github app/controllers/feed_previews_controller.rb test/controllers/feed_previews_controller_test.rb
git add app/controllers/feed_previews_controller.rb config/routes.rb test/controllers/feed_previews_controller_test.rb
git commit -m "Unify FeedPreviewsController: user-scoped, credential gate, params source"
```

---

## Phase E — Views: one set of partials, repoint the form, drop show-page button

### Task E1: Consolidate preview partials

**Files:**
- Create/keep: `app/views/feed_previews/_ready.html.erb`, `_processing.html.erb`, `_failed.html.erb`, `_credential_gate.html.erb`, `show.html.erb`
- Delete: duplicate partials under `app/views/feeds/` (`_preview*`) and `app/views/feeds/previews/`

- [ ] **Step 1: Author the four partials**

Reuse the existing markup. Each renders inside the `feed-preview` turbo frame.

`app/views/feed_previews/_processing.html.erb`:

```erb
<turbo-frame id="feed-preview"
             data-controller="polling"
             data-polling-endpoint-value="<%= feed_preview_path(preview, format: :turbo_stream) %>"
             data-key="preview.processing">
  <p class="text-slate-500">Building a preview…</p>
</turbo-frame>
```

`app/views/feed_previews/_ready.html.erb`:

```erb
<turbo-frame id="feed-preview" data-key="preview.ready">
  <% preview.posts_data.each do |post| %>
    <%= render PostPreviewComponent.new(post: post) %>
  <% end %>
</turbo-frame>
```

`app/views/feed_previews/_failed.html.erb`:

```erb
<turbo-frame id="feed-preview" data-key="preview.failed">
  <p class="text-red-600">We couldn't build a preview for this source. Double-check the link and try again.</p>
  <%= button_to "Try again", feed_previews_path,
                params: { profile_key: preview.feed_profile_key, params: preview.params },
                method: :post, class: "btn-secondary", form: { class: "inline-block" } %>
</turbo-frame>
```

`app/views/feed_previews/_credential_gate.html.erb`:

```erb
<turbo-frame id="feed-preview" data-key="preview.credential_gate">
  <p class="text-slate-600">This source uses AI, so you'll need an active AI credential to preview it.</p>
  <%= link_to "Add an AI credential", new_llm_credential_path, class: "btn-primary" %>
</turbo-frame>
```

Keep `app/views/feed_previews/show.html.erb` rendering the matching partial for the `html` format.

- [ ] **Step 2: Delete the duplicate live-stack partials**

```bash
git rm app/views/feeds/_preview.html.erb app/views/feeds/_preview_loading.html.erb app/views/feeds/_preview_failed.html.erb
git rm -r app/views/feeds/previews
```

(If `PostPreviewComponent` expects a different shape than `posts_data` hashes, adapt the `_ready` partial to the component's existing API — see `test/components/post_preview_component_test.rb`.)

- [ ] **Step 3: Commit**

```bash
git add -A app/views/feed_previews
git commit -m "Consolidate preview partials into feed_previews views"
```

### Task E2: Repoint the form preview pane

**Files:**
- Modify: `app/views/feeds/_form_expanded.html.erb:66-83`

- [ ] **Step 1: Replace the live_preview frame with the unified endpoint**

```erb
      <% unless edit_mode %>
        <div class="mt-2" data-key="form.preview">
          <%= turbo_frame_tag "feed-preview",
                              src: feed_previews_path(
                                profile_key: feed.feed_profile_key,
                                params: { feed.source_input_shape => feed.source_input }
                              ),
                              loading: "lazy" do %>
            <p class="text-slate-500">Building a preview…</p>
          <% end %>
        </div>
      <% end %>
```

This requires a `Feed#source_input_shape` helper returning the profile's input_shape key (defaulting to `"url"`).

- [ ] **Step 2: Add `Feed#source_input_shape`**

In `app/models/feed.rb`, near `source_input`:

```ruby
  def source_input_shape
    (FeedProfile[feed_profile_key]&.dig(:input_shape) || :url).to_s
  end
```

- [ ] **Step 3: Manual smoke (documented)**

Run: `bin/rails test test/integration/smart_feed_creation_rss_test.rb`
Expected: PASS after Phase G test updates; for now confirm the form renders without raising (the integration suite exercises this frame).

- [ ] **Step 4: Commit**

```bash
git add app/views/feeds/_form_expanded.html.erb app/models/feed.rb
git commit -m "Point feed form preview pane at unified controller (input_shape-aware)"
```

### Task E3: Drop the show-page Preview button

**Files:**
- Modify: `app/views/feeds/show.html.erb:35-44`
- Test: `test/controllers/feeds_controller_test.rb`

- [ ] **Step 1: Write a failing test**

```ruby
test "#show should not render a preview button" do
  sign_in_as(user)
  get feed_url(feed)
  assert_select "form[action='#{feed_previews_path}']", count: 0
end
```

- [ ] **Step 2: Remove the Preview `button_to` block** (the `if @feed.can_be_previewed?` action button) from `app/views/feeds/show.html.erb`.

- [ ] **Step 3: Run test**

Run: `bin/rails test test/controllers/feeds_controller_test.rb -n "/should not render a preview button/"`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add app/views/feeds/show.html.erb test/controllers/feeds_controller_test.rb
git commit -m "Remove show-page preview button; preview lives in create/edit"
```

---

## Phase F — Enable gate: DB query replaces `PreviewToken`

### Task F1: Replace the gate; delete the token

**Files:**
- Modify: `app/models/feed.rb` (gate + remove `preview_token` attr)
- Modify: `app/controllers/feeds_controller.rb:55,92` (remove `preview_token` plumbing)
- Modify: `app/views/feeds/_preview.html.erb` (already deleted in E1 — confirm no `preview_token` hidden field survives)
- Delete: `app/services/preview_token.rb`, `test/services/preview_token_test.rb`
- Test: `test/models/feed_test.rb`

- [ ] **Step 1: Add a shared test helper**

Create `test/support/preview_helpers.rb`:

```ruby
module PreviewHelpers
  # Seed the persisted proof the enable gate now looks for.
  def seed_ready_preview(feed, ready_at: Time.current)
    create(:feed_preview, :completed,
           user: feed.user,
           feed_profile_key: feed.feed_profile_key,
           params: feed.params,
           ready_at: ready_at)
  end
end
```

Require + include it in `test/test_helper.rb`:

```ruby
require_relative "support/preview_helpers"
# inside class ActiveSupport::TestCase
include PreviewHelpers
```

- [ ] **Step 2: Rewrite the gate tests in `test/models/feed_test.rb`**

Replace each `feed.preview_token = ...` setup with `seed_ready_preview(feed, ...)`. Canonical conversions:

```ruby
test "#enable should require a recent ready preview" do
  feed = build(:feed, :disabled) # no preview seeded
  feed.user.save! if feed.user.new_record?
  feed.save!
  refute feed.enable
  assert_includes feed.errors[:state], "requires a recent preview"
end

test "#enable should succeed with a fresh ready preview" do
  feed = create(:feed, :disabled)
  seed_ready_preview(feed)
  assert feed.enable
  assert feed.enabled?
end

test "#enable should reject a stale preview" do
  feed = create(:feed, :disabled)
  seed_ready_preview(feed, ready_at: 2.hours.ago)
  refute feed.enable
end

test "#enable should reject a preview for different params" do
  feed = create(:feed, :disabled, params: { "url" => "https://a.test" })
  create(:feed_preview, :completed, user: feed.user,
         feed_profile_key: feed.feed_profile_key,
         params: { "url" => "https://b.test" }, ready_at: Time.current)
  refute feed.enable
end
```

Delete the tampered/expired-token tests (token no longer exists); the stale test covers expiry.

- [ ] **Step 3: Implement the gate; drop `preview_token`**

In `app/models/feed.rb`: delete `attr_accessor :preview_token`, and replace `enabling_requires_recent_preview`:

```ruby
  ENABLE_PREVIEW_WINDOW = 60.minutes

  def enabling_requires_recent_preview
    fresh = FeedPreview.fresh_ready(
      user_id: user_id,
      feed_profile_key: feed_profile_key,
      params: params || {},
      within: ENABLE_PREVIEW_WINDOW
    )
    errors.add(:state, :preview_required, message: "requires a recent preview") unless fresh
  end
```

Keep the `validate :enabling_requires_recent_preview, on: :enable` line unchanged — the trigger surface is identical, so the status toggle still bypasses it by design.

- [ ] **Step 4: Remove controller plumbing**

In `app/controllers/feeds_controller.rb`, delete both `@feed.preview_token = params[:preview_token]` lines (create ~55, update ~92).

- [ ] **Step 5: Update the feed factory**

In `test/factories/feeds.rb`, inside the existing `after(:build)` block, delete **only** the final clause that signs a token (leave the access_token and feed_profile_key clauses intact):

```ruby
      # delete this clause:
      if feed.state == "enabled" && feed.preview_token.nil?
        feed.preview_token = PreviewToken.sign(
          user_id: feed.user&.id,
          profile_key: feed.feed_profile_key,
          params: feed.params,
          generated_at: Time.current
        )
      end
```

The `state { :enabled }` trait sets state directly; the default save context skips the enable gate, so no token/preview is needed for factory-built enabled feeds.

- [ ] **Step 6: Delete the token**

```bash
git rm app/services/preview_token.rb test/services/preview_token_test.rb
```

- [ ] **Step 7: Run model tests**

Run: `bin/rails test test/models/feed_test.rb`
Expected: PASS.

- [ ] **Step 8: RuboCop + commit**

```bash
bin/rubocop -f github app/models/feed.rb app/controllers/feeds_controller.rb test/models/feed_test.rb test/factories/feeds.rb test/test_helper.rb
git add -A app/models/feed.rb app/controllers/feeds_controller.rb test/ 
git commit -m "Enable gate: query fresh FeedPreview, delete PreviewToken"
```

### Task F2: Convert the remaining `preview_token` test sites

**Files:**
- Modify: `test/controllers/feeds_controller_test.rb` (lines ~80, 88, 123, 158, 166, 196, 210, 580, 590, 606)
- Modify: `test/integration/smart_feed_creation_rss_test.rb`, `smart_feed_creation_ai_website_test.rb`, `smart_feed_creation_state_gating_test.rb`, `feed_draft_flow_test.rb`
- Modify: `test/controllers/feeds/previews_controller_test.rb` → delete (folded into D1's suite)

- [ ] **Step 1: Find every remaining reference**

Run: `grep -rn "preview_token\|PreviewToken\|FeedPreviewService" test/`
Expected: a finite list; convert each.

- [ ] **Step 2: Apply the conversion pattern**

For form-promotion tests that posted `preview_token:` in params, drop that param and instead seed a row before the request:

```ruby
# before:
preview_token = PreviewToken.sign(user_id: user.id, profile_key: "rss", params: feed_params[:params], generated_at: Time.current)
post feeds_path, params: { feed: feed_params, enable_feed: "1", preview_token: preview_token }

# after:
create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
       params: feed_params[:params], ready_at: Time.current)
post feeds_path, params: { feed: feed_params, enable_feed: "1" }
```

For "missing token" / "tampered token" cases, simply omit the seed (assert the draft re-render with the preview-required error).

- [ ] **Step 3: Delete the folded controller test**

```bash
git rm test/controllers/feeds/previews_controller_test.rb
```

- [ ] **Step 4: Run the affected suites**

Run: `bin/rails test test/controllers/feeds_controller_test.rb test/integration/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A test/
git commit -m "Migrate preview_token tests to seeded FeedPreview rows"
```

---

## Phase G — AI prompt rendering + active-credential gate

> **Task G1 is DONE — delivered in PR #440** (`{{input}}` rendering + handle-profile
> removal). The original G1 text below is retained for history; skip it. Only **Task
> G2** (active-credential gate) is in scope for PR2.

### Task G1: Generalize `LlmLoader#rendered_prompt` — ✅ DONE in PR #440

**Files:**
- Modify: `app/services/loader/llm_loader.rb:37-40`
- Test: `test/services/loader/llm_loader_test.rb` (create if absent)

- [ ] **Step 1: Write failing tests**

```ruby
require "test_helper"

class Loader::LlmLoaderTest < ActiveSupport::TestCase
  test "#rendered_prompt should substitute the profile's input_shape source" do
    feed = build(:feed, feed_profile_key: "llm_handle_search", params: { "handle" => "@someone" })
    loader = Loader::LlmLoader.new(feed)
    loader.stub(:config, { prompt_template: "Follow {{handle}} now ({{input}})" }) do
      assert_equal "Follow @someone now (@someone)", loader.send(:rendered_prompt)
    end
  end

  test "#rendered_prompt should still substitute url for url profiles" do
    feed = build(:feed, feed_profile_key: "rss", params: { "url" => "https://x.test" })
    loader = Loader::LlmLoader.new(feed)
    loader.stub(:config, { prompt_template: "Load {{url}}" }) do
      assert_equal "Load https://x.test", loader.send(:rendered_prompt)
    end
  end
end
```

- [ ] **Step 2: Run to confirm failure**

Run: `bin/rails test test/services/loader/llm_loader_test.rb`
Expected: FAIL (`{{handle}}` not substituted).

- [ ] **Step 3: Implement**

```ruby
    def rendered_prompt
      source = feed.source_input.to_s
      config.fetch(:prompt_template).to_s
            .gsub("{{url}}", source)
            .gsub("{{input}}", source)
            .gsub("{{#{feed.source_input_shape}}}", source)
    end
```

- [ ] **Step 4: Run tests**

Run: `bin/rails test test/services/loader/llm_loader_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
bin/rubocop -f github app/services/loader/llm_loader.rb test/services/loader/llm_loader_test.rb
git add app/services/loader/llm_loader.rb test/services/loader/llm_loader_test.rb
git commit -m "LlmLoader: render prompt from profile input_shape source"
```

### Task G2: Treat an inactive attached credential as unusable

**Files:**
- Modify: `app/controllers/feed_previews_controller.rb` (`needs_credential_gate?`)
- Test: `test/controllers/feed_previews_controller_test.rb`

- [ ] **Step 1: Write a failing test**

```ruby
test "#create should gate AI preview when the only credential is inactive" do
  sign_in_as(user)
  create(:llm_credential, :inactive, user: user)
  post feed_previews_path, params: { profile_key: "llm_website_extractor", params: { url: "https://x.test" } }, as: :turbo_stream
  assert_select "[data-key='preview.credential_gate']"
  assert_equal 0, FeedPreview.count
end
```

(Use the `:inactive` credential trait if it exists; otherwise build one and set its state.)

- [ ] **Step 2: Confirm `needs_credential_gate?` already uses `.active`** — the controller from D1 already checks `Current.user.llm_credentials.active.exists?`, so an inactive-only user is gated. Run the test:

Run: `bin/rails test test/controllers/feed_previews_controller_test.rb -n "/inactive/"`
Expected: PASS. If it fails, ensure the gate uses the `active` scope as written.

- [ ] **Step 3: Commit**

```bash
git add test/controllers/feed_previews_controller_test.rb
git commit -m "Gate AI preview when no active credential exists"
```

---

## Phase H — Retention sweeper

### Task H1: Prune job + schedule

**Files:**
- Create: `app/jobs/prune_feed_previews_job.rb`
- Modify: `config/recurring.yml`
- Test: `test/jobs/prune_feed_previews_job_test.rb`

- [ ] **Step 1: Write failing test**

```ruby
require "test_helper"

class PruneFeedPreviewsJobTest < ActiveJob::TestCase
  test "#perform should delete previews older than the retention window" do
    old = create(:feed_preview, created_at: 8.days.ago)
    recent = create(:feed_preview, created_at: 1.hour.ago)

    PruneFeedPreviewsJob.perform_now

    assert_not FeedPreview.exists?(old.id)
    assert FeedPreview.exists?(recent.id)
  end
end
```

- [ ] **Step 2: Confirm failure**

Run: `bin/rails test test/jobs/prune_feed_previews_job_test.rb`
Expected: FAIL (class undefined).

- [ ] **Step 3: Implement the job**

```ruby
# Removes stale preview rows. The enable gate only honors previews newer than
# Feed::ENABLE_PREVIEW_WINDOW, so anything older than RETENTION is safe to drop.
class PruneFeedPreviewsJob < ApplicationJob
  queue_as :default

  RETENTION = 7.days

  def perform
    FeedPreview.where(created_at: ..RETENTION.ago).in_batches(of: 500).delete_all
  end
end
```

- [ ] **Step 4: Schedule it** in `config/recurring.yml` under both `development` and `production`:

```yaml
  prune_feed_previews:
    class: PruneFeedPreviewsJob
    queue: default
    schedule: every day at 4am
```

- [ ] **Step 5: Run test**

Run: `bin/rails test test/jobs/prune_feed_previews_job_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
bin/rubocop -f github app/jobs/prune_feed_previews_job.rb test/jobs/prune_feed_previews_job_test.rb
git add app/jobs/prune_feed_previews_job.rb config/recurring.yml test/jobs/prune_feed_previews_job_test.rb
git commit -m "Add PruneFeedPreviewsJob retention sweeper"
```

---

## Phase I — Delete the legacy stack and final sweep

### Task I1: Remove `FeedPreviewService` and the nested controller

**Files:**
- Delete: `app/services/feed_preview_service.rb`, `test/services/feed_preview_service_test.rb`
- Delete: `app/controllers/feeds/previews_controller.rb`
- Grep: confirm no references remain

- [ ] **Step 1: Delete the files**

```bash
git rm app/services/feed_preview_service.rb test/services/feed_preview_service_test.rb app/controllers/feeds/previews_controller.rb
```

- [ ] **Step 2: Confirm nothing references them**

Run: `grep -rn "FeedPreviewService\|feed_live_preview_path\|Feeds::PreviewsController\|DRAFT_FEED_ID" app/ test/ config/`
Expected: no matches. Fix any stragglers (e.g. integration tests still calling `FeedPreviewService.call` must move to `FeedPreviewJob` / seeded rows).

- [ ] **Step 3: Run the full suite**

Run: `bin/rails test`
Expected: PASS (0 failures, 0 errors).

- [ ] **Step 4: RuboCop the whole diff**

Run: `bin/rubocop -f github`
Expected: no offenses.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Remove cache-based preview service and nested controller"
```

### Task I2: Final verification

- [ ] **Step 1: Migration round-trips on a populated DB**

Run: `bin/rails db:migrate:redo`
Expected: down then up succeed.

- [ ] **Step 2: Full suite + lint once more**

Run: `bin/rails test && bin/rubocop -f github`
Expected: all green.

- [ ] **Step 3: Grep for dead references**

Run: `grep -rn "preview_token\|PreviewToken\|AdminFeedPreviewJob" app/ test/ config/ db/schema.rb`
Expected: no matches.

---

## Self-Review Notes

- **Spec coverage:** model generalization (A), workflow on transient feed + run_id (B), one job (C), unified user-scoped controller + credential gate + blank-source (D), view consolidation + form repoint + show-button drop (E), DB-query enable gate + token deletion + ~40 test conversions (F), AI prompt/credential caveats (G), retention sweeper (H), legacy deletion + drift-guard via shared workflow tests (I). All spec sections map to a task.
- **Type consistency:** `FeedPreview.digest_for` / `fresh_ready` / `Feed#source_input_shape` / `Feed::ENABLE_PREVIEW_WINDOW` are defined once and reused verbatim across tasks.
- **Drift guard:** Phase B's workflow tests plus the RSS/AI integration tests are the shared loader→processor→normalizer coverage the spec asks for; no base class introduced.
