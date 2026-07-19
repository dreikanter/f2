# Rate limit policies for external APIs. See docs/rate-limiting.md.
#
# Wrapped in to_prepare so RateLimit (an autoloaded app constant) is available
# and policies are re-registered on code reload in development.
#
# FreeFeed meters per HTTP method, per authenticated user. Limits below sit under
# FreeFeed's ceilings (freefeed-server config/default.js, authenticated.maxRequests;
# keyed by method in app/support/rateLimiter.ts — see docs/rate-limiting-freefeed.md):
#
#   POST            60/min  — every POST a publish makes: the post itself, each
#                             comment, and each attachment upload (POST /v1/attachments)
#   GET            200/min  — whoami, managedGroups (token validation)
#   DELETE (`all`)  30/min  — post withdrawal / group purge (1 DELETE per post)
#
# FreeFeed counts each ceiling over a *rolling* one-minute window, so the most a
# token bucket can legally spend in any single window is burst + rate (a full
# bucket plus a minute of refill). Each burst below is therefore capped so that
# burst + rate stays under the ceiling with margin to spare — the same account
# may also be used by a human or other clients, and breaching gets the whole
# account blocked for 1–8 minutes (escalating), including the FreeFeed UI.
#
# FreeFeed also allows GET /vN/attachments/:attId/:type 1000/min, but that's the
# attachment-download route, which Feeder never calls — so it gets no bucket.
Rails.application.config.to_prepare do
  RateLimit.define :freefeed do
    limit :post, 30, per: 1.minute, burst: 20   # worst window 50, under FreeFeed POST 60/min
    limit :get, 100, per: 1.minute, burst: 30   # worst window 130, under FreeFeed GET 200/min
    limit :delete, 15, per: 1.minute, burst: 10 # worst window 25, under FreeFeed `all` fallback 30/min
  end

  # Per-credential webhook ingress limit. This protects the database and keeps a
  # runaway sender from monopolizing the account's FreeFeed publish budget.
  # Public ingress fails closed if limiter storage is unavailable.
  RateLimit.define :webhook_ingest do
    limit :request, 60, per: 1.minute, burst: 10
    fail_open false
  end
end
