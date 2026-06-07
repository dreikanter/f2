# Rate limit policies for external APIs. See docs/rate-limiting.md.
#
# Wrapped in to_prepare so RateLimit (an autoloaded app constant) is available
# and policies are re-registered on code reload in development.
#
# FreeFeed meters per HTTP method (see docs/rate-limiting-freefeed.md), so every
# POST a publish makes — the post itself, each comment, AND each attachment
# upload (POST /v1/attachments) — counts against the same POST bucket. We use a
# single :post dimension set below FreeFeed's 60 POST/min ceiling. (The 1000/min
# attachments limit FreeFeed documents is for GET downloads, not uploads.)
Rails.application.config.to_prepare do
  RateLimit.define :freefeed do
    limit :post, 50, per: 1.minute # under FreeFeed's 60 POST/min
  end
end
