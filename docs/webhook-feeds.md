# Webhook feeds

A webhook feed has no source to poll. You push posts into it over HTTP instead:
one request, one post, published to the feed's FreeFeed group through the same
pipeline every other feed uses. It's the feed type for a cron script, a CI job,
or anything that already has the content in hand.

## Setting up the feed

On **New Feed**, pick **Post via webhook** and continue. There's no source to
enter and nothing to detect, so you go straight to the full feed form.

Give the feed a name, pick an access token and a target group, and save it. The
endpoint and its token are minted on that first save, and from then on they live
on the feed's page. Enable the feed when you're ready; there's no schedule to
set, since nothing is being polled.

The endpoint answers `409` until the feed is enabled, and disabling the feed
pauses it again. A paused feed makes the caller's script fail loudly instead of
posting into the void.

## The endpoint and its token

Every webhook feed posts to the same URL:

```
POST /v1/posts
```

The 43-character bearer token is the whole auth model — it identifies *and*
authenticates the feed, so nothing in the request names the feed itself. No
signature scheme, no handshake.

```
Authorization: Bearer <token>
```

The feed page carries a **Webhook API** panel with the URL, the token, a
ready-to-paste curl command, and when the endpoint last received something.
Treat the token like a password. If it leaks, **Generate new token** replaces it
in place and the old one stops authenticating immediately.

## Sending a post

Only `application/json` is accepted, and each request carries at most one post.

```sh
curl --request POST https://feeder.example/v1/posts \
  --header "Authorization: Bearer TOKEN" \
  --header "Content-Type: application/json" \
  --data '{"content":"Hello world"}'
```

Everything the payload accepts:

```sh
curl --request POST https://feeder.example/v1/posts \
  --header "Authorization: Bearer TOKEN" \
  --header "Content-Type: application/json" \
  --data '{
    "content": "Look at this",
    "source_url": "https://example.com/article",
    "images": ["https://example.com/pic.jpg"],
    "comments": ["First comment", "Second comment"],
    "uid": "article-42",
    "published_at": "2026-07-11T12:00:00Z"
  }'
```

| Field | Type | Notes |
| --- | --- | --- |
| `content` | string | The post body. Required unless `images` is non-empty. |
| `source_url` | string | Absolute `http(s)` URL, up to 2048 characters. Appended to the body (see below) and used as the uid seed. |
| `images` | array of strings | Up to 8. Each must be an absolute, public `http(s)` URL; Feeder downloads them and re-uploads them to FreeFeed at publish time. Images alone are a complete post. |
| `comments` | array of strings | Up to 8, published as comments under the post. Each is clamped to 3000 characters. |
| `uid` | string | 1–255 characters. Your idempotency key — see [Retries and duplicates](#retries-and-duplicates). |
| `published_at` | string | ISO 8601. Defaults to now; a future timestamp is clamped to now. Controls publish order. |

Every field is optional on its own, but a payload with neither `content` nor
`images` is a `422`. Unknown fields are rejected rather than ignored, so a typo
like `imges` comes back as a `422` instead of quietly publishing a post with no
images.

Two things about `content` that aren't guessable from the field names:

- **`source_url` is appended to the body**, joined with ` - `, the same shape
  pull feeds produce. If you also put the link in `content`, it appears twice.
- **Content is truncated, never rejected.** The 3000-character budget is shared
  with the appended link, so content shorter than 3000 can still be trimmed to
  make the URL fit. You get the post plus a `content_truncated` warning in the
  `201`.

## Responses

Every response is JSON except `413`, so a script can branch on `status`.

| Status | Body | Meaning |
| --- | --- | --- |
| `201` | `{"status": "enqueued", "uid": "…", "warnings": [...]}` | Accepted. `warnings` is present only when non-empty. |
| `200` | `{"status": "duplicate", "uid": "…"}` | This uid already exists on this feed. Nothing was created. |
| `400` | `{"status": "bad_request"}` | The body isn't parseable JSON. |
| `401` | `{"status": "unauthorized"}` | Missing, malformed, unknown, or rotated token. Carries `WWW-Authenticate`. |
| `409` | `{"status": "feed_not_enabled"}` | The token is good, but the feed is a draft or disabled. |
| `413` | — | Body over 128 KB. |
| `415` | `{"status": "unsupported_media_type"}` | Content type other than `application/json`. |
| `422` | `{"status": "invalid", "errors": ["…"]}` | Validation failed. **Nothing was persisted.** |
| `429` | `{"status": "throttled"}` | Ingress rate limit. Carries `Retry-After` in seconds. |

A `201` means **enqueued, not published**. Publishing happens asynchronously
behind the FreeFeed rate limiter, so nothing that goes wrong afterwards can reach
the response you already have.

Where those failures surface depends on what failed. A dead access token, a
target group you've lost access to, and comments that couldn't be delivered each
write an entry to the feed's **Recent Activity**. Everything else — an image URL
that 404s, an unexpected fault — only marks the post failed, with nothing in the
activity log. Check the feed's posts as well as its activity when a delivery you
got a `201` for never shows up.

## Retries and duplicates

Every post gets a uid, and a uid that already exists on the feed is answered with
`200 duplicate` — no second post, no matter how the content changed since. Where
that uid comes from, in order:

1. The **`uid` field**.
2. The **`Idempotency-Key` header**, which is just a second spelling of `uid`.
   Send both and they must match, or the request is a `422`.
3. **`source_url`**, normalized the way pull feeds normalize permalinks: coerced
   to `https`, `www.` and tracking parameters stripped. One permalink, one post.
4. A **random UUID** — a new post every time.

So: **pass a `uid` if your delivery can retry.** Without one, a retry after a
network timeout double-posts, unless `source_url` happens to be carrying the
identity for you. Note that `source_url` only anchors identity when it's a deep
link; a bare homepage falls back to a random uid like a missing URL would.

`Idempotency-Key` accepts both a bare value and the quoted RFC 8941 form
(`"key-1"`), and decodes the quoted one, so the same logical key matches whether
it arrived in the header or the body.

A `422` deliberately persists **nothing** — no post, no uid record. That's what
makes a corrected retry go through instead of coming back as `duplicate`.

## Limits

| Limit | Value |
| --- | --- |
| Requests | 60/min per endpoint, burst 10 |
| Images | 8 per post |
| Comments | 8 per post |
| Body size | 128 KB, checked before parsing |

The rate limit is a token bucket: from idle you can fire 10 requests
back-to-back, then roughly one per second. Over it, you get `429` with
`Retry-After`. It protects the database and keeps one runaway script from eating
the account's FreeFeed publish budget, so it fails closed — if the limiter's
storage is unavailable, the endpoint throttles rather than waving traffic
through.

The image and comment caps are load-bearing rather than arbitrary. Publishing
one post costs `1 + comments + images` FreeFeed writes against a burst capacity
of 20, and a post whose cost exceeds that capacity can never publish.
`1 + 8 + 8 = 17` keeps every accepted delivery publishable, so rejecting an
oversized payload at ingress beats accepting it and failing it silently later.
