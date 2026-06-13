# FreeFeed Server API Rate Limiting

How the FreeFeed server limits API requests. Useful as a reference when
deciding how Feeder should pace its requests to avoid HTTP 429 responses.

> Source: [FreeFeed/freefeed-server](https://github.com/FreeFeed/freefeed-server)
> at commit `35b39a6` (2026-05-13). The counting algorithm lives in the
> [`async-ratelimiter`](https://github.com/microlinkhq/async-ratelimiter) package
> that FreeFeed pins at `~1.6.4`. See [Source references](#source-references) at
> the bottom for the specific files and symbols behind each claim below.

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

## How the window is counted (sliding window log)

This is the part that matters most when pacing our own requests, and it is easy
to get wrong by assuming a fixed window.

`async-ratelimiter` is a **sliding window log**, not a fixed-window counter and
not a token bucket. Each allowed request is stored as one member in a Redis
sorted set, scored by its timestamp. On every call it:

1. drops members older than `now - duration` (`ZREMRANGEBYSCORE`),
2. counts what remains (`ZCARD`),
3. allows the request iff `count < max`, recording it (`ZADD`).

So the rule is exact and unforgiving: **at most `max` requests in any rolling
`duration`** — measured continuously, not reset on a clock boundary. There is no
separate "burst" allowance on top of the rate; `max` *is* the burst and the rate
at once.

Two consequences that drive our client config:

- You **can** legally fire all 60 POSTs in one instant, but then you must wait
  until the oldest of them ages out of the trailing minute before the next one
  is admitted. There is no steady "60/min drip" assumption to lean on.
- Because the window slides, a limiter on our side that allows `burst + rate`
  tokens within one window (a token bucket) can exceed `max` even when each of
  `burst` and `rate` looks safe. That is exactly why Feeder caps each dimension
  so that `burst + rate` stays under the FreeFeed ceiling — see
  [`docs/rate-limiting.md`](rate-limiting.md) and
  `config/initializers/rate_limits.rb`.

> Caveat: subjects differ between the two sides. FreeFeed keys per **account**
> (user id); Feeder keys per **access-token**. Multiple tokens for one FreeFeed
> user share one server-side sliding window but get independent buckets on our
> side, so exact parity is impossible — keep headroom under the ceiling.

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

## Source references

Each claim above was confirmed against source at the pinned versions, not
inferred. Links are permalinks at FreeFeed commit `35b39a6` and
`async-ratelimiter` tag `v1.6.4`.

| Claim | Where to confirm |
|-------|------------------|
| Limit values (auth POST 60, GET 200, `all` 30; anon GET 100, `all` 10; attachments 1000), window `PT1M`, `blockDuration PT1M`, `repeatBlockMultiplier 2`, `repeatBlockCounterDuration PT10M` | [`config/default.js`](https://github.com/FreeFeed/freefeed-server/blob/35b39a6/config/default.js) → `rateLimit` |
| Middleware, per-`clientId + method` keying, block check before counting, escalation on repeat breaches | [`app/support/rateLimiter.ts`](https://github.com/FreeFeed/freefeed-server/blob/35b39a6/app/support/rateLimiter.ts) |
| Route/method/`all` precedence; `/vN` version normalization | [`app/routes.js`](https://github.com/FreeFeed/freefeed-server/blob/35b39a6/app/routes.js), [`rateLimiter.ts`](https://github.com/FreeFeed/freefeed-server/blob/35b39a6/app/support/rateLimiter.ts) |
| HTTP 429 with body `"Slow down"` (`TooManyRequestsException`) | [`app/support/exceptions.js`](https://github.com/FreeFeed/freefeed-server/blob/35b39a6/app/support/exceptions.js) |
| Sliding-window-log algorithm: sorted set, `ZREMRANGEBYSCORE` → `ZCARD` → `ZADD`, `remaining = max - count`, no burst-on-top | [`async-ratelimiter` `src/index.js`](https://github.com/microlinkhq/async-ratelimiter/blob/v1.6.4/src/index.js), pinned in FreeFeed [`package.json`](https://github.com/FreeFeed/freefeed-server/blob/35b39a6/package.json) (`~1.6.4`) |

Verified 2026-06-13. The only thing not read line-by-line is FreeFeed's exact
`repeat`-block arithmetic; the `1 → 2 → 4 → 6 → 8 min` ladder above is the
illustrative result of `2 × prior blocks`, not a literal table in the source.
