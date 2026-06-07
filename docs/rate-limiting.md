# Generalized Request Rate Limiting (Working Draft)

> **Status:** working draft — design agreed, not yet implemented. Captures the
> concepts, public API, storage, and integration plan for a shared
> rate-limiting mechanism.

## Goal

A single rate-limiting mechanism that works across multiple external API
providers and use cases, rather than one-off throttling per integration. It
should be:

- **Generalized** — not tied to any one provider's quirks.
- **Reusable** — usable from any service or job that calls an external API.
- **Robust and easy to understand** — a small surface, predictable behavior,
  easy to configure and reason about.

### Motivating use cases

- **Posting to FreeFeed** — per-account, per-method limits with escalating
  server-side blocks (see [`rate-limiting-freefeed.md`](rate-limiting-freefeed.md)).
- **LLM APIs** — used mainly during content loading and initial processing
  (e.g. fetching web/search results, normalizing content). These limit on more
  than one axis at once: requests-per-minute *and* tokens-per-minute.
- **Arbitrary content loaders** — politeness limits when fetching from the web,
  typically per-domain.

> **Scope:** this mechanism handles **time-windowed rate limiting** only —
> "may I make this call right now?". Two related concerns are deliberately
> *out of scope*: depletable **quotas/budgets** that don't reset on a clock
> (API credits, monthly op counts, proxy bandwidth — usually best read from the
> provider's own balance endpoint), and **scheduling** (feed refresh intervals
> belong to the scheduler, not here).

## Core concepts

The whole model is a few ideas:

- **Policy** — a named profile for one provider (`:freefeed`, `:openai`,
  `:web_fetch`). A policy declares one or more limits.
- **Dimension** — the axis being metered (`requests`, `tokens`, `posts`). Cost
  is charged per dimension.
- **Limit** — a single rule on a dimension: a `rate` over a `window`, with an
  optional `burst` capacity (the bucket size, which can exceed the per-window
  rate to allow short bursts / averaging windows). A policy can have several
  limits, because one call may be constrained on multiple axes **and** on
  multiple windows of the *same* axis — e.g. requests per-minute *and*
  per-day.
- **Subject** — the identity *within* a provider that owns the allowance
  (a FreeFeed access-token id, an LLM API key, a domain). Each subject is
  metered independently.
- **Bucket** — the unit of persisted state: one token bucket per
  `(dimension, window)`. Multiple windows on the same dimension (e.g. requests
  per-minute *and* per-day) are just separate buckets. Single-dimension is the
  special case of one bucket; multi-dimension is the general case.

A call consumes some **cost** from one or more dimensions of a policy, on
behalf of a subject. That single shape covers every use case:

| Use case            | Policy       | Subject              | Dimensions (cost)               |
|---------------------|--------------|----------------------|---------------------------------|
| Post to FreeFeed    | `:freefeed`  | `freefeed:<token id>`| `post: N` (post + comments + uploads) |
| LLM fetch/processing| `:openai`    | api-key id           | `requests: 1`, `tokens: ~1500`  |
| Web fetch (loader)  | `:web_fetch` | domain               | `requests: 1`                   |

The dimension idea is what makes the LLM case work: a single request draws from
both a requests bucket and a tokens bucket, with different costs, and is allowed
only if *every* limit it touches has room (across all dimensions and all of
their windows).

Some costs aren't fully known until *after* the call — LLM output tokens, or
bytes actually transferred. For those, the caller charges an **estimate** up
front and **reconciles** the difference once the real figure is known (see the
API below). This keeps fast-moving dimensions like output-tokens-per-minute
from drifting.

## Choosing the granularity

The subject should match what the *remote* provider actually meters on, so our
local accounting mirrors theirs:

- **Per provider identity, not global** — e.g. FreeFeed limits per account, so
  one busy account must not throttle unrelated ones. A global cap would be both
  too strict and too loose.
- **Not too fine** — several feeds under the same FreeFeed token share one
  remote bucket, so the subject is the token's identity, not the feed.

For FreeFeed the subject is the **access-token id** (`freefeed:<id>`). FreeFeed
actually meters per account, so multiple tokens for the same FreeFeed user share
its real bucket; keying per token over-counts in that rare case, but the `429`
backstop covers it. A token id is stable and always present (unlike `owner`,
which is unknown until validation), so it avoids a shifting subject.

## Public API (sketch)

The intended surface is small — a few entry points and a result object. Names
are provisional.

```ruby
# Non-blocking check — returns a result, never raises for being over-limit
result = RateLimit.acquire(:openai, subject: key_id, cost: { requests: 1, tokens: est })
result.allowed?      # => true / false
result.retry_after   # => seconds to wait when not allowed

# Raising variant — pairs with the job-reschedule pattern below
RateLimit.acquire!(:openai, subject: key_id, cost: { ... })   # raises RateLimit::Throttled

# Block form — for inline (non-job) call sites
RateLimit.throttle(:web_fetch, subject: domain) { http.get(url) }

# True up a dimension after the fact, when the real cost is only known
# post-call (LLM output tokens, actual bytes). Adjusts the earlier estimate.
RateLimit.reconcile(:openai, subject: key_id, cost: { tokens: actual - estimated })

# Feed the provider's own verdict back in (e.g. on a real 429)
RateLimit.penalize(:openai, subject: key_id, retry_after: 30)
```

### Configuration (sketch)

Policies are declared up front, in plain, readable terms:

```ruby
RateLimit.define :freefeed do
  limit :requests, 25, per: 1.minute   # stay under the provider's ceiling
  limit :posts,    50, per: 1.minute
end

RateLimit.define :openai do
  limit :requests, 500,     per: 1.minute   # the same dimension can carry
  limit :requests, 10_000,  per: 1.day      # more than one window
  limit :tokens,   200_000, per: 1.minute
end

RateLimit.define :reddit do
  # burst > rate models an averaging window: 100/min averaged over ~10 min
  limit :requests, 100, per: 1.minute, burst: 1_000
end
```

`burst` defaults to the per-window `rate` when omitted (a strict window with no
slack).

## Algorithm: token bucket

Each bucket holds `tokens`, refilling at `rate = limit / window` (tokens/sec) up
to a cap of `burst`. A call spends `cost` tokens; if a bucket lacks them, the
call is throttled.

Refill is **lazy and continuous** — no timer, no scheduled reset. It's computed
on each acquire from the time elapsed since the bucket was last touched:

```
available   = min(burst, tokens + (now - refilled_at) * rate)
if available >= cost:
    tokens      = available - cost
    refilled_at = now
    → allow
else:
    → throttle, retry_after = (cost - available) / rate
```

This gives a rolling limit (not a fixed-window reset): a bucket regains
`rate` tokens/sec and saturates at `burst`. Set `burst = rate*window` for a
plain "N per window"; set `burst` higher to allow spikes / averaging windows.

Units are normalized to **seconds** (`window` in seconds, `rate` in
tokens/sec) to avoid unit bugs; config sugar like `per: 1.minute` is converted
on load.

## Storage

A **single PostgreSQL table**, one row per `(policy, subject)`. All of that
subject's buckets live in one **JSONB** column; only mutable state is persisted
(`rate`/`burst`/`window` stay in config).

```
key          text   -- "policy:subject", e.g. "freefeed:7"
data         jsonb  -- { "post/1m": {tokens, refilled_at}, ... }
blocked_until timestamptz  -- set by penalize() on a real 429; short-circuits acquire
```

One JSONB row per subject (rather than a row per bucket) keeps a multi-dimension
acquire to a **single row** — one lock, atomic all-or-nothing, no deadlock
ordering. At Feeder's scale (<10 users) Postgres is more than sufficient; no
Redis.

## Concurrency & atomicity

`acquire` must be atomic against parallel jobs sharing a subject, or two jobs
race and over-admit. Atomicity comes from the database, not an app-level lock:

- **Single dimension** — one `UPDATE … WHERE available >= cost RETURNING …`.
  Postgres serializes concurrent writers to the same row; 0 rows back =
  throttled.
- **Multi-dimension (all-or-nothing)** — a short transaction: `SELECT … FOR
  UPDATE` the subject's row, compute every bucket in Ruby, then update all of
  them or none. One row = one lock.

Different subjects are different rows, so they never contend — serialization
happens only per subject, which is exactly where it's wanted.

## Usage patterns

Two patterns cover essentially everything:

1. **Guard inside the API client.** The client layer knows the provider's
   semantics (which dimension a call costs, how to read a `Retry-After`), so it
   asks the limiter before each call and reports real `429`s back via
   `penalize`.

2. **Reschedule, don't block, in background jobs.** When a call is throttled, a
   job should *defer itself* (re-enqueue with a wait) rather than sleep and hold
   a worker. This turns rate limiting into natural backpressure: the producer's
   effective rate self-adjusts to what the provider will accept.

## Integration model

All external API interaction happens **from jobs**, so throttling becomes a
reschedule rather than a blocked worker. The flow:

1. **Reserve the whole job's cost up front**, in one `acquire!`, *before* any
   API call. A job computes its total cost ahead of time (for FreeFeed publish:
   `{ post: 1 + comments + attachments }` — attachment uploads are POSTs too).
2. **Throttled → reschedule** the job with `wait: retry_after` (+ jitter).
   Nothing was sent, so there's no partial work.
3. **Granted → run all calls straight through** without re-consulting the
   limiter; capacity is already reserved. No mid-job throttling.
4. **Real `429` → `penalize`** sets `blocked_until` for the subject; subsequent
   `acquire!`s short-circuit until then, so jobs reschedule.

Add a **retry cap** (max attempts / total delay) so a job can't reschedule
forever — give up to the error reporter instead.

### Why reserve up front (no resumability)

Multi-call jobs (publish = attachments + post + comments) must not be throttled
mid-sequence, because re-running from the top would duplicate work, and there's
no resumable/draft state. Reserving the full cost atomically up front avoids
this without resumability. **Accepted for now:** if FreeFeed itself returns a
`429` mid-sequence (despite our local limit sitting under theirs), a partially
published post may remain. That's a pre-existing property of non-transactional
multi-call publishing, not introduced by the limiter.

### Where it hooks into FreeFeed services

- **`FreefeedClient`** — single chokepoint; the job reserves cost before driving
  the client. The client translates a `429` into `penalize` + a throttle error.
- **Jobs** (`PostWithdrawalJob`, `TokenValidationJob`, and the publish path) —
  rescue the throttle error and reschedule.
- FreeFeed cost is a request count known up front, so **no `reconcile`** is
  needed for it (reconcile is for token/byte costs).

## Principles

- **The provider's response is the source of truth.** Local limits are a
  predictor that keeps us comfortably under the ceiling; an actual `429` (and
  its `Retry-After`) always wins and triggers a cooldown for that subject. This
  is what keeps us out of FreeFeed's escalating-block spiral and honors LLM
  rate-limit headers.
- **Set local limits below the provider's real limits** to leave a safety
  margin.
- **Estimate up front, reconcile after** for costs that aren't known until the
  response arrives (output tokens, bytes). The estimate prevents overshoot; the
  reconciliation prevents drift.
- **Behavior under the limiter's own failure is a deliberate choice** per
  policy: fail *open* for politeness limits (the remote still protects itself),
  more conservative for cost-bearing calls like LLMs.

## Known limitations (acceptable for a first version)

- **Reacts to `429`, doesn't pre-sync from headers.** Providers return live
  `remaining`/`reset` headers; the limiter ignores them and relies on
  conservative local limits plus `penalize` on a real `429`. Ingesting those
  headers to correct local state is a possible later refinement, not required
  for correctness.
- **Per-IP limits under proxy rotation.** When egress IPs rotate (a residential
  proxy pool), provider limits scoped *per IP* no longer map to a stable
  subject. Such limits would need the current IP as part of the subject, or to
  be left to the remote's `429`.

## Provider coverage

The model was checked against the providers Feeder may integrate. Each maps to
buckets keyed per `(dimension, window)`:

| Provider    | Buckets                                                    |
|-------------|-----------------------------------------------------------|
| FreeFeed    | `post/1m` (post + comments + uploads), `get/1m`, `delete/1m` |
| Anthropic   | `requests/1m`, `input_tokens/1m`, `output_tokens/1m`      |
| OpenAI      | `requests/1m`, `requests/1d`, `tokens/1m`, `tokens/1d`    |
| OpenRouter  | `requests/1m`, `requests/1d`                              |
| Reddit      | `requests/1m` with `burst ≈ 1000` (10-min averaging)      |
| HN-Algolia  | `requests/1h`                                             |
| rss.app     | `requests/1s`                                             |

Token-based dimensions (Anthropic/OpenAI) additionally use `reconcile` for
post-call truing-up. Depletable quotas (credits, monthly ops, proxy bandwidth)
are **out of scope** — see Scope above.

## Open questions (to resolve before implementation)

- The per-provider heuristic for the up-front cost *estimate* (e.g. how to
  predict LLM output tokens before the call).
- Whether to also lean on Solid Queue concurrency controls as a complementary
  mechanism.

## References

- [`rate-limiting-freefeed.md`](rate-limiting-freefeed.md) — the first intended
  consumer; FreeFeed becomes one policy under this design.
