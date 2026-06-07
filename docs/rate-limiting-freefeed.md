# FreeFeed Server API Rate Limiting

How the FreeFeed server limits API requests. Useful as a reference when
deciding how Feeder should pace its requests to avoid HTTP 429 responses.

> Source: [FreeFeed/freefeed-server](https://github.com/FreeFeed/freefeed-server)
> at commit `35b39a6` (2026-05-13). Key files: `app/support/rateLimiter.ts`,
> `config/default.js`, `app/routes.js`, `app/support/exceptions.js`.

## Where it runs

A single Koa middleware (`rateLimiterMiddleware`) backed by Redis, applied to
every public and admin API route. It runs after JWT decoding, so it knows the
caller's identity. Counters use the `async-ratelimiter` package.

## How a client is identified

- **Authenticated** request → keyed by **user ID**, uses the `authenticated`
  limits.
- **Anonymous** request → keyed by **IP address** (`ctx.ip`), uses the
  `anonymous` limits.

Counters are per `clientId + HTTP method`, so each method is tracked
separately for each client.

## Default limits

Configured in `config.rateLimit` (`config/default.js`). The time window is an
ISO-8601 duration; default is `PT1M` (1 minute). **Each value below is a
separate per-method bucket — there is no combined cap across methods.** `all`
is *not* an aggregate; it is the fallback limit for methods without their own
entry (`DELETE`, `PUT`, `PATCH`…), and each such method still gets its own
bucket using that value.

| Auth type     | Window | `all` (fallback) | `GET` | `POST` | Attachments (`GET /vN/attachments/:attId/:type`) |
|---------------|--------|------------------|-------|--------|--------------------------------------------------|
| Anonymous     | 1 min  | 10               | 100   | —      | 1000                                             |
| Authenticated | 1 min  | 30               | 200   | 60     | 1000                                             |

Limit resolution precedence (most to least specific):

1. Exact route (e.g. `GET /vN/attachments/:attId/:type`; the version prefix is
   normalized to `/vN`).
2. HTTP method (`GET`, `POST`, …). `HEAD` counts as `GET`.
3. Fallback `all`.

## What happens when you exceed the limit

Going over the allowance does **not** just throttle the next request — the
client gets **blocked**, and repeat offenders are punished progressively
(`rateLimiter.ts`):

- **First breach:** blocked for `blockDuration` (default `PT1M`, 1 min).
- **Repeat breaches within the memory window:** block duration is multiplied
  (`repeatBlockMultiplier` = 2 × number of previous blocks). Block times grow
  roughly 1 → 2 → 4 → 6 → 8 minutes.
- The "memory" of past breaches (`repeatBlockCounterDuration`, default `PT10M`)
  is extended with each breach (≈11 → 12 → 14 → 16 minutes). Behave for the
  full window and all past breaches are forgiven.
- While blocked, every request is rejected immediately without consulting the
  per-method counters.

### Response

Exceeding the limit (or being blocked) returns **HTTP 429** with the body
message `"Slow down"` (`TooManyRequestsException`, `exceptions.js`).

## Bypasses and toggles

- **Disabled by default** (`config.rateLimit.enabled = false`). A deployment
  must opt in.
- **Allowlist** (`config.rateLimit.allowlist`, default `['::ffff:127.0.0.1']`)
  skips all limiting. Entries can be IP addresses or user IDs.

## Practical implications for Feeder

- Authenticate requests where possible — authenticated limits are ~3× higher
  than anonymous ones (per user, not per shared IP).
- Limits are per method, not combined. The one that matters for publishing is
  ~60 POST/min per account (each post can be several POSTs: attachments + post
  + comments). `GET` is far more generous at 200/min, and methods without their
  own entry fall back to 30/min each. Keep a safety margin since each bucket is
  a strict 1-minute window.
- On a 429, **back off** rather than retry immediately — repeated breaches
  escalate the block duration and reset the forgiveness window. A clean pause
  of several minutes is the fastest way back to normal.
- Bulk attachment fetches (`GET /vN/attachments/:attId/:type`) get a much
  higher cap (1000/min).
