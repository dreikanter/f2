# FreeFeed Server API Rate Limiting

How the FreeFeed server limits API requests — a reference for pacing Feeder's
requests to avoid HTTP 429s.

> Source: [FreeFeed/freefeed-server](https://github.com/FreeFeed/freefeed-server)
> at commit `35b39a6` (2026-05-13); the counting algorithm is the
> [`async-ratelimiter`][async-ratelimiter] package it pins at `~1.6.4`
> ([`package.json`][package.json]). Inline file links are permalinks at those
> versions.

## Where it runs

A single Koa middleware (`rateLimiterMiddleware`, [`rateLimiter.ts`][ratelimiter])
backed by Redis, applied to every public and admin API route. It runs after JWT
decoding, so it knows the caller's identity.

## How a client is identified

- **Authenticated** → keyed by **user ID**, uses the `authenticated` limits
  (~3× the anonymous ones).
- **Anonymous** → keyed by **IP address** (`ctx.ip`), uses the `anonymous` limits.

Counters are per `clientId + HTTP method`: each method is tracked separately for
each client.

## Default limits

From `config.rateLimit` ([`config/default.js`][default]). Each value is a
separate per-method bucket — there is no combined cap across methods. `all` is
the fallback for methods without their own entry (`DELETE`, `PUT`, `PATCH`…);
each such method still gets its own bucket at that value.

| Auth type     | Window | `all` (fallback) | `GET` | `POST` | Attachments (`GET /vN/attachments/:attId/:type`) |
|---------------|--------|------------------|-------|--------|--------------------------------------------------|
| Anonymous     | 1 min  | 10               | 100   | —      | 1000                                             |
| Authenticated | 1 min  | 30               | 200   | 60     | 1000                                             |

Resolution precedence, most to least specific ([`routes.js`][routes],
[`rateLimiter.ts`][ratelimiter]):

1. Exact route (e.g. `GET /vN/attachments/:attId/:type`; the version prefix is
   normalized to `/vN`).
2. HTTP method (`HEAD` counts as `GET`).
3. Fallback `all`.

## How the window is counted

`async-ratelimiter` ([`src/index.js`][async-ratelimiter]) is a **sliding window
log**. Each allowed request is stored as one member in a Redis sorted set, scored
by timestamp. On every call it drops members older than `now - duration`
(`ZREMRANGEBYSCORE`), counts the rest (`ZCARD`), and allows the request only if
`count < max`, recording it (`ZADD`).

The rule is therefore **at most `max` requests in any rolling `duration`** (window
default `PT1M`, 1 min), measured continuously rather than reset on a clock
boundary. `max` is the only parameter: there is no separate burst allowance on
top of a rate.

This shapes how Feeder paces itself:

- All `max` requests may go out at once, but the next is admitted only once the
  oldest ages out of the trailing window.
- A token bucket on our side admits up to `burst + rate` within one window, which
  can exceed `max` even when `burst` and `rate` each look safe. Feeder caps each
  dimension so `burst + rate` stays under the FreeFeed ceiling — see
  [`rate-limiting.md`](rate-limiting.md) and `config/initializers/rate_limits.rb`.
- FreeFeed keys its counter on the authenticated account (the JWT user id), shared
  across all of that account's tokens. Feeder keys its subject the same way once a
  token is validated (`freefeed:<instance>:<user_id>`), so sibling tokens for one
  account share a single local bucket and can't each spend a separate allowance.

## Exceeding the limit

Going over does not just delay the next request — the client is **blocked**, and
repeat breaches escalate ([`rateLimiter.ts`][ratelimiter]):

- The first breach blocks for `blockDuration` (1 min).
- The Nth consecutive breach blocks for `blockDuration × repeatBlockMultiplier ×
  (N − 1)`; with `repeatBlockMultiplier = 2` that is 2, 4, 6, 8 min for the 2nd
  through 5th.
- Each breach extends the memory window (`repeatBlockCounterDuration`, 10 min)
  that decides what counts as "consecutive"; stay clean for its full length and
  the count resets.
- While blocked, every request is rejected without consulting the per-method
  counters.

A blocked or over-limit request returns **HTTP 429** with body `"Slow down"`
(`TooManyRequestsException`, [`exceptions.js`][exceptions]) and no `Retry-After`.
Because breaches escalate and reset the forgiveness window, back off for minutes
after a 429 rather than retrying immediately.

## Bypasses and toggles

- **Disabled by default** (`config.rateLimit.enabled = false`); a deployment must
  opt in.
- **Allowlist** (`config.rateLimit.allowlist`, default `['::ffff:127.0.0.1']`)
  skips limiting; entries are IPs or user IDs.

## What this means for publishing

Each publish is several POSTs (the post, each comment, each attachment upload), so
the **60 POST/min** authenticated bucket is the binding constraint; `GET`
(200/min) and the `all` fallback (30/min) are rarely close. Authenticate so these
higher per-user limits apply.

[default]: https://github.com/FreeFeed/freefeed-server/blob/35b39a6/config/default.js
[ratelimiter]: https://github.com/FreeFeed/freefeed-server/blob/35b39a6/app/support/rateLimiter.ts
[routes]: https://github.com/FreeFeed/freefeed-server/blob/35b39a6/app/routes.js
[exceptions]: https://github.com/FreeFeed/freefeed-server/blob/35b39a6/app/support/exceptions.js
[package.json]: https://github.com/FreeFeed/freefeed-server/blob/35b39a6/package.json
[async-ratelimiter]: https://github.com/microlinkhq/async-ratelimiter/blob/v1.6.4/src/index.js
