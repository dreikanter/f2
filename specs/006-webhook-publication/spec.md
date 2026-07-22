# Webhook publication (push feeds)

**Date**: 2026-07-11 |
**Status**: Proposed — architecture design, not yet implemented

**Related**: [`001-smart-feed-creation`](../001-smart-feed-creation/spec.md) (feed pipeline),
[`005-feed-creation-ux-ai-overhaul`](../005-feed-creation-ux-ai-overhaul/spec.md) (creation modes,
profile registry shape, SSRF guard)

This is the design/rationale record for webhook-based publication: feeds that receive content
from incoming HTTP requests instead of pulling it from a source. It may ship across multiple PRs.
Where the code later diverges, the code is the source of truth; this document records *why* the
decisions were made.

## Why

Every existing profile is **pull**: a scheduled refresh loads a source, extracts entries, and
publishes new ones. There is no way to *push* content into a Freefeed group from the outside —
a cron script, a CI job, a home-automation hook, another app. Users who already have the content
in hand shouldn't need to stand up an RSS feed just so Feeder can poll it back.

The requirements, in the user's terms:

- Each webhook feed enables a **shared endpoint with a unique secret token** that accepts data for **one post at a time**
  and publishes to the group configured for that feed.
- Hassle-free: a working post should be a single **curl** command with no client library, no
  signature dance, no multi-step handshake.
- Images and comments should work, with the simplest possible interface.

## Core mental model

**A webhook feed is a feed whose loader is the outside world.** Everything after the entry
exists is the pipeline we already have: uid dedup (`FeedEntryUid`), normalization into a `Post`,
content validation, the per-feed FIFO publish chain (`PostPublishJob`), FreeFeed rate limiting,
publish-failure handling (token/group auto-disable), and the feed page / posts / activity UI.
Only acquisition differs — push instead of pull, synchronous instead of scheduled, one post per
request instead of a batch.

So the design is: a new **`webhook` feed profile** (no matcher, no loader, no schedule) plus one
new ingress path (`POST /v1/posts`) that validates the payload, persists a
`FeedEntry` + `Post` through the profile's normalizer, and kicks the existing publish chain.
Nothing downstream changes.

```
curl → POST /v1/posts (Authorization: Bearer <token>)
         │ authenticate token → feed (401 unknown, 409 not enabled, 429 throttled)
         │ validate payload against request schema        → 422 with details
         │ resolve uid (explicit > source_url > random)   → 200 duplicate
         │ normalize via Normalizer::WebhookNormalizer
         │ transaction: FeedEntry + FeedEntryUid + Post(enqueued)
         │ PostPublishJob.perform_later(feed.id)          ← existing FIFO chain
         └ 201 {status: "enqueued", uid: ...}
```

### Alternative considered: staged deliveries through the refresh pipeline

A tempting full-reuse variant: the controller stores raw payloads in a staging table and kicks
`FeedRefreshJob`; a `Loader::WebhookLoader` drains staged deliveries so `FeedRefreshWorkflow`
runs untouched. Rejected:

- It **loses synchronous feedback** — the whole point of a curl-friendly API is that a bad
  payload comes back as an immediate 422 with the reason, not a silent 202 followed by an event
  the user has to go find.
- Every delivery would mint a `feed_refresh` event; a chatty hook floods the activity log.
- It adds a staging table *and* a loader/processor pair, which is more machinery than the direct
  path it was supposed to save.

The direct path still reuses the parts that carry real invariants: the uid dedup mechanism, the
normalizer contract (`Normalizer::Base` validation, SSRF filtering, comment clamping), the `Post`
state machine, and the publish chain.

## Decisions

### 1. A feed profile, not a parallel mechanism

Register a `webhook` profile in `FeedProfile::PROFILES`:

- **No matcher** — structurally excluded from URL detection, same mechanism as the AI profile
  (spec 005 §7). You get a webhook feed only by choosing it.
- **No loader, no processor** — there is nothing to fetch. A new registry flag (`push: true`)
  marks the profile as push-ingested; `FeedProfile.push?(key)` is the single predicate the rest
  of the app reads. Refresh and preview surfaces are gated on it (§7), so the nil stages are
  never resolved.
- **Normalizer**: `Normalizer::WebhookNormalizer` — the one pipeline stage a push feed genuinely
  has. It converts the stored payload (`FeedEntry#raw_data`) into a `Post` and inherits the
  choke-point guarantees from `Normalizer::Base` for free: `PublicUrl.safe?` filtering of
  attachment URLs (SSRF, spec 005 §8), comment clamping, `images_only` support, future-date
  clamping, and the no-content-no-images rejection rule.
- **`parameter_schema`**: an empty object (`additionalProperties: false`) — a webhook feed has
  no source input. `input_shape: :none`. `Feed#source_input` is nil, which automatically turns
  off preview (`can_be_previewed?` requires a source) without special-casing.

Keeping it a profile means every generic surface — feed list, feed page, posts, events, purge,
withdraw, admin — works unchanged, and profile-driven branching stays in the registry instead of
spreading `if webhook?` checks around.

### 2. The endpoint: a shared URL, a secret bearer token

- **Route**: `POST /v1/posts`, handled by a dedicated single-action controller
  (`Api::V1::PostsController#create`, built on `ActionController::API`, so there is no session,
  CSRF, or browser surface to skip). The token travels in the `Authorization: Bearer` **header**
  — the endpoint URL is shared by all webhook feeds, and the token alone identifies and
  authenticates the feed. No signature scheme; the token *is* the credential.
- **Token**: `SecureRandom.urlsafe_base64(32)` (256 bits, ~43 chars). Unguessable; HTTPS
  everywhere in production, so the path is protected in transit.
- **Storage**: a new 1:1 model rather than columns on `feeds`:

  ```
  webhook_endpoints
    feed_id       uuid, null: false, unique index   (has_one from Feed, dependent: :destroy)
    token         encrypted (deterministic), unique index — the lookup key
    last_received_at datetime
    received_count   integer, default 0, null: false
    created_at / updated_at
  ```

  (`feed_id` is `uuid` like every other reference — the schema uses uuidv7 primary keys
  throughout.)

  Deterministic AR encryption (`encrypts :token, deterministic: true`) gives one column that is
  both queryable (`find_by(token:)` through a unique index) and re-displayable in the UI — the
  user can copy the token from the feed page any time, not only at creation. A separate table
  (instead of a `feeds` column, despite the `ai_model` precedent) keeps secret material out of
  `feed.attributes`, which is attached verbatim to error-tracking context by `PostPublishJob`.
- **Lifecycle**: the endpoint row is minted when the webhook feed is created (drafts included),
  so the endpoint URL, token, and a ready-to-paste curl snippet are visible immediately. It dies
  with the feed.
- **Rotation**: a "Generate new token" action on the feed page replaces the token in place; the
  old token is rejected (401) from that moment. This is the remedy for a leaked token, so it
  must be one click.

### 3. The request contract (the curl contract)

Only `application/json` is accepted — other media types are rejected up front (415), so a
misconfigured caller gets an explicit answer instead of a silently misparsed body:

```sh
# minimal
curl https://feeder.example/v1/posts \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content": "Hello world"}'

# everything
curl https://feeder.example/v1/posts \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "content": "Look at this",
        "source_url": "https://example.com/article",
        "images": ["https://example.com/pic.jpg"],
        "comments": ["First comment", "Second comment"],
        "uid": "article-42",
        "published_at": "2026-07-11T12:00:00Z"
      }'
```

Fields (all top-level; validated with JSONSchemer, the same library that validates profile
params):

| Field | Type | Rules |
|---|---|---|
| `content` | string | Post body. Required unless `images` is non-empty (mirrors the pipeline's no-content-no-images rule). Truncated to FreeFeed's 3000-grapheme limit rather than rejected — length never fails a request; a `content_truncated` warning is returned instead. |
| `source_url` | string | Optional. Appended to the body via the house `post_content_with_url` convention (same "link + commentary" shape as pull feeds) and used as the uid seed (§4). Must be an absolute http(s) URL. |
| `images` | array of strings | Optional, max 8. Each must be an absolute, public http(s) URL — checked with `PublicUrl.safe?` at ingress so an unsafe URL is an explicit 422, and filtered again at the normalizer choke point (defense in depth). Downloaded and re-uploaded to FreeFeed at publish time by the existing `FileBuffer` path. |
| `comments` | array of strings | Optional, max 8. Published as FreeFeed comments after the post, with the existing best-effort semantics (a mid-publish throttle can drop trailing comments; never duplicates). Clamped to 3000 chars each. |
| `uid` | string | Optional idempotency key, ≤ 255 chars. See §4. |
| `published_at` | string | Optional ISO-8601; defaults to now; future values clamped to now (existing `Normalizer::Base` behavior). Controls publish order within the FIFO chain. |

The **caps on `images` and `comments` are load-bearing**, not taste: publishing costs
`1 + comments + images` FreeFeed POSTs against a burst capacity of 20 (see
`config/initializers/rate_limits.rb`), and `PostPublishJob` permanently fails any post whose
cost exceeds capacity. `1 + 8 + 8 = 17` keeps every accepted webhook post publishable. Rejecting
oversized payloads at ingress (422) is strictly friendlier than accepting them and letting the
publisher fail them silently later.

**Responses** — JSON in all cases, so scripts can branch on them:

| Status | Body | Meaning |
|---|---|---|
| 201 | `{"status": "enqueued", "uid": "...", "warnings": [...]}` | Accepted; will publish asynchronously through the FIFO chain. `warnings` (e.g. `content_truncated`) present only when non-empty. |
| 200 | `{"status": "duplicate", "uid": "..."}` | This uid was already ingested for this feed; nothing new created. Safe retry. |
| 422 | `{"status": "invalid", "errors": ["..."]}` | Payload failed validation. **Nothing is persisted** (§4), so a corrected retry goes through cleanly. |
| 401 | `{"status": "unauthorized"}` + `WWW-Authenticate` | Missing, malformed, unknown, or rotated bearer token. |
| 409 | `{"status": "feed_not_enabled"}` | Valid token, but the feed is a draft or disabled. Pausing a feed pauses its endpoint. |
| 413 | — | Body over the ingress cap (order of 128 KB — far above any legitimate post). |
| 415 | `{"status": "unsupported_media_type"}` | Content type other than `application/json`. |
| 400 | `{"status": "bad_request"}` | Body isn't parseable JSON. |
| 429 | `{"status": "throttled"}` + `Retry-After` | Ingress rate limit (§6). |

The 201 means **enqueued, not on FreeFeed** — publication stays asynchronous behind the rate
limiter. This is the honest contract: publish-side failures (invalid token, lost group) surface
in the feed's activity log through the existing event machinery, exactly as for pull feeds.

### 4. Identity and idempotency

Dedup reuses `FeedEntryUid` unchanged; the only question is where a webhook post's uid comes
from. Precedence:

1. **Explicit `uid`** — the caller's idempotency key. Redelivering the same uid returns
   `200 duplicate` no matter how the content changed. This is the documented answer for
   at-least-once delivery pipelines.
2. **`source_url`**, normalized the same way `Uid::Resolver` normalizes permalinks (https
   coercion, `www.`/tracking-param stripping), so the identity semantics match pull feeds: one
   permalink, one post.
3. **Random UUID** — each request creates a new post. A blind curl retry after a network timeout
   can double-post; the docs say "pass `uid` if your delivery can retry".

Two concurrent deliveries of the same uid can both pass the pre-insert dedup check; the
`(feed_id, uid)` unique index is the arbiter. The ingestion transaction maps
`ActiveRecord::RecordNotUnique` to the same `200 duplicate` as the sequential case, so the
loser of the race gets the honest answer instead of a 500.

One deliberate divergence from the pull pipeline: a payload that fails validation persists
**nothing** — no `FeedEntry`, no rejected `Post`, no uid record. Pull feeds persist rejected
posts so their uids stay recorded across refreshes; that logic protects a *pull* loop from
re-importing garbage forever. For push, the request itself is the retry mechanism, and recording
the uid of a rejected payload would make the *corrected* retry come back as `duplicate` — the
opposite of helpful. The synchronous 422 is the rejection record.

### 5. Images and comments: the simplest interface that works

**v1: images are URLs, not uploads.** The payload takes public image URLs; at publish time the
existing path (`FileBuffer` download → FreeFeed attachment upload) does the heavy lifting, with
`PublicUrl.safe?` already guarding SSRF at the normalizer choke point. This covers the standard
automation cases (the image is already hosted somewhere) with zero new infrastructure and keeps
the curl call a one-liner.

Direct binary upload (`curl -F "image=@photo.jpg"`) is **deferred, with a sketched path**:
publishing is asynchronous and rate-limited, so uploaded bytes must be persisted until the FIFO
chain drains — that means ActiveStorage blobs, an internal blob-reference scheme in
`attachment_urls` that `FileBuffer` resolves at publish, and purge-after-terminal-state
retention. Real scope, nothing about v1's contract blocks adding it later (a multipart request
would simply populate `images` server-side).

**Comments are just strings.** `comments: [...]` maps straight onto `Post#comments`, which the
publisher already turns into FreeFeed comments. No threading, no authorship options — the feed's
token authors everything, same as pull feeds. Combined with `source_url` folding into the body,
the classic Feeder post shape (text + link, images attached, commentary below) is fully
expressible from one curl command.

### 6. Security

- **Bearer token**: 256-bit random token; possession is authorization. Missing, malformed, or
  unknown token → uniform 401. Lookup is a unique-index equality on deterministic ciphertext —
  no length/timing oracle worth exploiting.
- **Rotation** (§2) is the leak remedy; it's instant and self-service.
- **Log hygiene**: the token rides in the `Authorization` header — not the URL path — so it
  stays out of request-path access logs and pasted URLs. The header still must not be echoed
  into error-tracking context or log payloads.
- **Ingress rate limit**: a new `RateLimit.define :webhook_ingest` policy (existing token-bucket
  service, subject = endpoint), around 60 requests/min with a small burst. It protects the DB
  and keeps one runaway script from monopolizing the account's FreeFeed publish budget. 429 +
  `Retry-After` mirrors the limiter's contract.
- **Payload cap** at the controller (≈128 KB) before any parsing.
- **SSRF**: image URLs validated with `PublicUrl.safe?` at ingress (explicit 422) *and* filtered
  at `Normalizer::Base#attachment_urls` (silent drop) — the second check is the invariant, the
  first is ergonomics.
- **No CSRF/session surface**: the controller never touches a session; forgery protection is
  skipped like the Resend webhook.

### 7. Feed lifecycle and UX

- **Creation**: a third creation mode alongside "Follow a feed or channel" / "Follow with AI" —
  "**Post via webhook**" (copy TBD per UI-text guidelines). No source field, no identification
  step, no preview, no schedule picker: it goes straight to the expanded form as a draft with the
  endpoint already minted, showing the URL and a copyable curl example.
- **Schedule-less by design**: the `push: true` registry flag exempts webhook feeds from the
  cron requirement — `cron_expression` presence-if-enabled, `can_be_enabled?`, and
  `create_schedule_on_enable` all consult it. A schedule-less enabled feed is **not** naturally
  invisible to the scheduler — `Feed.due` deliberately matches enabled feeds *without* a
  `FeedSchedule` row (`feed_schedules.id IS NULL`, its self-heal branch), and
  `FeedSchedulerJob` would then mint an initial schedule and enqueue a refresh every minute.
  So push profiles are excluded explicitly: `Feed.due` filters them out
  (`where.not(feed_profile_key: ...push keys...)`), and `FeedRefreshJob` no-ops on a push feed
  as a second layer — the exclusion is the invariant, the job guard is defense in depth, same
  shape as the SSRF checks (§6). Manual refresh and preview surfaces are hidden/rejected for
  push profiles (both actions are meaningless without a loader).
- **Enable gate**: name + active access token + target group — the standard set minus cron. The
  endpoint answers 409 until the feed is enabled, so "draft → configure → enable → curl works"
  is the whole onboarding.
- **Feed page** additions for push feeds: the endpoint URL and token with copy buttons, the curl
  snippet, "Generate new token", and "last received N minutes ago" (from
  `webhook_endpoints.last_received_at`).
  Refresh/schedule/preview affordances disappear.
- **Failure handling**: `consecutive_failures` auto-disable is refresh-side and simply never
  triggers (nothing increments it). Publish-side protection is inherited unchanged: an invalid
  FreeFeed token disables the token and its feeds; a lost/restricted target group disables just
  the feed with an explanatory event. A disabled feed's endpoint returns 409, so the caller's
  script fails loudly instead of posting into the void.

### 8. Observability

- **Counters, not events, for the happy path**: `last_received_at` and `received_count` on the
  endpoint row, plus a `webhook_ingest_total{status:}` metric through the existing `Metrics`
  service. `last_received_at` updates on every authenticated, well-formed delivery (a `201`
  or a `200 duplicate` both prove the caller's script is alive — the answer to "is my hook
  still working"); `received_count` counts only accepted posts (`201`). Per-request `Event`
  records are deliberately avoided — a chatty hook would flood the activity feed, and the
  synchronous response already tells the caller everything about their request.
- **Events where they carry news the caller can't see**: publish failures downstream produce the
  same events as today (they're feed-level, not request-level, and the user needs to see them).

## Out of scope (explicitly)

- **Batch ingestion** — the contract is one post per request, per the requirements. A loop in
  the caller's script is the batch API.
- **Editing/withdrawing posts via webhook** — the UI already handles withdrawal; a mutable HTTP
  surface (needs per-post handles, auth semantics beyond the feed-level bearer token) is a
  different feature.
- **Direct binary upload** — deferred with a sketched design (§5).
- **HMAC signatures** — the bearer token is the auth model; signature verification belongs to
  webhooks we *consume* (Resend), not endpoints we *offer* to the user's own scripts.

## Delivery plan

Independent, reviewable steps; each keeps `main` shippable:

1. **Profile + model plumbing** — `push` registry flag and `FeedProfile.push?`, the `webhook`
   profile entry, `WebhookEndpoint` model + migration (reversible), `Feed` schedule-requirement
   exemptions, the `Feed.due` push exclusion + `FeedRefreshJob` guard (§7),
   `Normalizer::WebhookNormalizer`. No routes yet; pure additive.
2. **Ingress** — `Api::V1::PostsController`, the ingestion service (payload schema, uid
   resolution, transactional persist, publish kick), the `:webhook_ingest` rate-limit policy,
   response contract + request tests, log scrubbing.
3. **UX** — creation mode, feed-page endpoint panel (URL, curl snippet, rotate,
   last-received), refresh/preview gating in views, changelog entry.
4. **Later** — multipart image upload (v2), if demand materializes.
