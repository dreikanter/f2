# Rate limit policies for external APIs. See docs/rate-limiting.md.
#
# Wrapped in to_prepare so RateLimit (an autoloaded app constant) is available
# and policies are re-registered on code reload in development.
#
# FreeFeed meters per HTTP method (see docs/rate-limiting-freefeed.md). We set
# our limits below FreeFeed's defaults to keep a safety margin, and give
# attachment uploads their own (higher) bucket so a media-heavy post isn't
# throttled by the tighter post limit.
Rails.application.config.to_prepare do
  RateLimit.define :freefeed do
    limit :post, 50, per: 1.minute        # under FreeFeed's 60 POST/min
    limit :attachment, 500, per: 1.minute # under the 1000/min attachments-route bucket
  end
end
