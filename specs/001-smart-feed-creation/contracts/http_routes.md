# Contract: HTTP Routes & Turbo Stream Payloads

**Audience**: controller authors, JS controller authors, integration-test authors.
**Status**: planning-time (Phase 1 design output).

## Routes

### Modified

```ruby
# config/routes.rb
resources :feeds do
  resource :status, only: %i[update]                  # existing
  resource :purge,  only: %i[create]                  # existing
  resource :preview, only: %i[show create destroy]    # NEW — see below
end

resource :feed_details, only: %i[create show]         # existing; payload shape changes
```

### New

```ruby
resources :llm_credentials, except: %i[edit update] do
  resource :validation, only: %i[show]                # polling shell, like access_tokens
  resource :default,    only: %i[update]              # PATCH /llm_credentials/:id/default → set as default for its provider
end
```

No `member` / `collection` routes (constitution principle I). The `default` toggle is a singular nested resource (`update` = "make this the default").

## Endpoint contracts

### `POST /feed_details` (modified)

**Request**: form-encoded `{ url: "<user input>" }`. The param name stays `url` for backward-compat, but the backend treats it as the universal input string. Renamed param `input` would force a UI re-test pass; not worth it.

**Response**: Turbo Stream replacing `#feed-form` with `feeds/_identification_loading` partial.

**Side effect**: enqueues `FeedDetailsJob`.

### `GET /feed_details` (modified)

**Request**: no params (state is the user's most-recent in-progress `FeedDetail`).

**Response**: Turbo Stream replacing `#feed-form` based on the FeedDetail's status:
- `processing` → `feeds/_identification_loading` partial (continues polling).
- `success` → `feeds/_form_expanded` partial including the candidate chooser when `candidates.length > 1`, plus an embedded `<turbo-frame id="feed-preview" src="...">` that lazy-loads the preview.
- `failed` → `feeds/_form_expanded` partial in "AI fallback only" mode (curated AI candidates from `candidates`, never an error page).

### `GET /feeds/:feed_id/preview` (new)

**Purpose**: render the preview pane for the currently selected candidate.

**Request**: query params `profile_key`, `params` (JSON), `llm_credential_id?`.

**Response**:
- If cached: HTML for `feeds/_preview` partial with the `Preview` value object.
- If not cached: enqueues `FeedPreviewJob`, returns `feeds/_preview_loading` partial; the partial includes the polling target the Stimulus controller uses.

### `POST /feeds/:feed_id/preview` (new)

**Purpose**: explicit "Refresh preview" — bust cache, recompute.

**Side effect**: enqueues `FeedPreviewJob` with `refresh: true`. Returns `_preview_loading`.

### `DELETE /feeds/:feed_id/preview` (new)

**Purpose**: dismiss / clear preview state when user changes a non-source field that shouldn't trigger preview rerun (rarely used; here for UI completeness).

**Note on the `feed_id` segment**: previews of a *new* feed use `feed_id = "draft"` (string sentinel) — the controller checks for the sentinel and routes to in-memory preview state keyed by `feed_detail_id` instead of a real feed.

### `GET /llm_credentials` / `GET /llm_credentials/new` / `POST /llm_credentials` / `GET /llm_credentials/:id` / `DELETE /llm_credentials/:id` (new)

Standard resourceful CRUD. Mirrors `AccessTokensController` shape:
- `index` lists user's credentials grouped by provider (DaisyUI tabs).
- `new` renders a provider-picker → on provider selection, the form fields are generated from `LlmProvider::PROVIDERS[provider][:credential_schema]`.
- `create` enqueues `LlmCredentialValidationJob`; redirects to `show` (polling shell).
- `show` polls until `state` settles; renders status + provider details.
- `destroy` confirms via modal; nullifies dependent `feeds.llm_credential_id`; cascades to `disable_associated_feeds` for any feed left without a usable credential.

### `PATCH /llm_credentials/:id/default` (new)

**Request**: no body.

**Response**: redirect to `/llm_credentials` with a flash; or, with Accept: text/vnd.turbo-stream.html, a Turbo Stream that updates the row's "default" badge.

**Side effect**: in one transaction, set `is_default = false` on the previously-default credential for `(user_id, provider)`, set `is_default = true` on this one. Partial unique index makes this atomic.

### `GET /llm_credentials/:llm_credential_id/validation` (new)

Identical pattern to `access_token_validation_path`: polling endpoint that returns the current state of the validation job.

## Turbo Stream payloads (new)

### `feeds/_form_expanded` (with candidate chooser)

When `feed_detail.candidates.length > 1`, the partial includes:

```erb
<%= render "feeds/candidate_chooser", candidates: feed_detail.candidates %>
```

`_candidate_chooser` markup (sketch):

```erb
<div data-controller="candidate-chooser" data-key="candidates">
  <% candidates.each_with_index do |c, i| %>
    <label class="..." data-key="candidate.<%= c['profile_key'] %>">
      <input type="radio" name="feed[feed_profile_key]" value="<%= c['profile_key'] %>"
             <%= 'checked' if i == 0 %>
             data-action="change->candidate-chooser#switch"
             data-candidate-chooser-target="option">
      <span><%= profile_display_name(c['profile_key']) %></span>
      <% if c['depends_on_ai'] %>
        <span data-key="candidate.ai-badge">AI</span>
      <% end %>
    </label>
  <% end %>
</div>
```

`candidate-chooser` Stimulus controller emits a `feed:candidate-changed` event on switch; `preview-controller` listens for it and reloads the preview frame.

### `feeds/_preview` (success)

Renders 2–5 `PostDraft` cards in DaisyUI card style. Each card shows: title, body (truncated to 500 chars with "show more"), supplementary comments collapsed by default, attached image thumbnails, source URL. A "Refresh preview" button at the top of the pane (`data-action="click->preview#refresh"`).

### `feeds/_preview_failed`

Renders the failure copy from FR-017, a "Try again" button (calls `POST /feeds/:feed_id/preview`), and a "Save as disabled" button (submits the form with a hidden `enable_feed: 0` and a query param disabling the preview-token requirement).

## Test contract

- Controller tests assert payload shapes: Turbo Stream content type, partial used, `data-key` attributes present.
- Integration / system tests cover the full happy path for Story 1 (paste → poll → expanded form → preview → save → enabled feed exists) and for Story 2 (paste → poll → AI candidate → credentials gate → return → preview → save).
- Stimulus controller tests are out of scope for v1 (project doesn't use jest/vitest); behavior is validated by the system tests.
