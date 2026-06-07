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
# FreeFeed also allows GET /vN/attachments/:attId/:type 1000/min, but that's the
# attachment-download route, which Feeder never calls — so it gets no bucket.
Rails.application.config.to_prepare do
  RateLimit.define :freefeed do
    limit :post, 50, per: 1.minute   # under FreeFeed POST 60/min
    limit :get, 150, per: 1.minute   # under FreeFeed GET 200/min
    limit :delete, 25, per: 1.minute # under FreeFeed `all` fallback 30/min
  end
end
