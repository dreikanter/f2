# Generalized Request Rate Limiting (Working Draft)

> **Status:** working draft — conceptual design, not yet implemented.
> Captures the intended shape of a shared rate-limiting mechanism so we can
> agree on the concepts and public API before writing code.

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

## Core concepts

The whole model is three ideas:

- **Policy** — a named profile for one provider (`:freefeed`, `:openai`,
  `:web_fetch`). A policy declares one or more limits.
- **Limit (dimension)** — a single rate rule within a policy (a rate over a
  time window). A policy can have several, because one logical call may be
  constrained on multiple axes simultaneously.
- **Subject** — the identity *within* a provider that owns the allowance
  (a FreeFeed `host:owner`, an LLM API key, a domain). Each subject is metered
  independently.

A call consumes some **cost** from one or more dimensions of a policy, on
behalf of a subject. That single shape covers every use case:

| Use case            | Policy       | Subject        | Dimensions (cost)               |
|---------------------|--------------|----------------|---------------------------------|
| Post to FreeFeed    | `:freefeed`  | `host:owner`   | `posts: 1` (per method)         |
| LLM fetch/processing| `:openai`    | api-key id     | `requests: 1`, `tokens: ~1500`  |
| Web fetch (loader)  | `:web_fetch` | domain         | `requests: 1`                   |

The dimension idea is what makes the LLM case work: a single request draws from
both a requests bucket and a tokens bucket, with different costs, and is allowed
only if *all* of its dimensions have room.

## Choosing the granularity

The subject should match what the *remote* provider actually meters on, so our
local accounting mirrors theirs:

- **Per provider identity, not global** — e.g. FreeFeed limits per account, so
  one busy account must not throttle unrelated ones. A global cap would be both
  too strict and too loose.
- **Not too fine** — several feeds under the same FreeFeed token share one
  remote bucket, so the subject is the token's identity, not the feed.

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
  limit :requests,   500,     per: 1.minute
  limit :tokens,     200_000, per: 1.minute
end
```

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

## Principles

- **The provider's response is the source of truth.** Local limits are a
  predictor that keeps us comfortably under the ceiling; an actual `429` (and
  its `Retry-After`) always wins and triggers a cooldown for that subject. This
  is what keeps us out of FreeFeed's escalating-block spiral and honors LLM
  rate-limit headers.
- **Set local limits below the provider's real limits** to leave a safety
  margin.
- **Behavior under the limiter's own failure is a deliberate choice** per
  policy: fail *open* for politeness limits (the remote still protects itself),
  more conservative for cost-bearing calls like LLMs.

## Open questions (to resolve before implementation)

- Storage backend (Feeder is all-PostgreSQL via the Solid stack; no Redis).
- Limiting algorithm and exact semantics of a "window".
- How LLM token costs are estimated up front and reconciled against actual
  usage afterward.
- Whether to also lean on Solid Queue concurrency controls as a complementary
  mechanism.

## References

- [`rate-limiting-freefeed.md`](rate-limiting-freefeed.md) — the first intended
  consumer; FreeFeed becomes one policy under this design.
