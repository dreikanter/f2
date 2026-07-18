# The webhook capability token rides in the URL path, which shows up in access
# logs; filter_parameters only covers request params, so the path itself must
# be scrubbed (spec 006 §6). Registered as a semantic-logger hook, which drives
# request logging on the deployed environments only (see Gemfile).
module WebhookLogScrubbing
  TOKEN_IN_PATH = %r{(?<=/hooks/)[^/\s?"]+}

  def self.scrub(text)
    text.gsub(TOKEN_IN_PATH, "[FILTERED]")
  end

  def self.call(log)
    log.message = scrub(log.message) if log.message.is_a?(String)
    log.payload[:path] = scrub(log.payload[:path]) if log.payload.is_a?(Hash) && log.payload[:path].is_a?(String)
  end
end

SemanticLogger.on_log(WebhookLogScrubbing) if defined?(SemanticLogger)
