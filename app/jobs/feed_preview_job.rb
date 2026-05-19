# Async wrapper for FeedPreviewService.call. Writes the resulting
# Preview (or a failure marker on error) into Rails.cache so the
# polling shell on the feed creation form can pick it up.
class FeedPreviewJob < ApplicationJob
  queue_as :default

  FAILURE_TTL = 24.hours

  # @param args [Hash] keyword-like hash with stringified keys:
  #   - user_id           [Integer]
  #   - profile_key       [String]
  #   - params            [Hash]
  #   - cache_key         [String]
  #   - llm_credential_id [Integer, nil]
  #   - limit             [Integer, optional]
  def perform(args)
    args = args.deep_stringify_keys
    cache_key = args.fetch("cache_key")
    user = User.find_by(id: args.fetch("user_id"))
    return unless user

    llm_credential = LlmCredential.find_by(id: args["llm_credential_id"]) if args["llm_credential_id"]

    FeedPreviewService.call(
      user: user,
      profile_key: args.fetch("profile_key"),
      params: args.fetch("params", {}),
      llm_credential: llm_credential,
      cache_key: cache_key,
      refresh: true,
      limit: args.fetch("limit", 5)
    )
  rescue FeedPreviewService::Error => e
    Rails.error.report(e, context: { user_id: args["user_id"], profile_key: args["profile_key"] })
    Rails.cache.write(
      cache_key,
      { error: e.class.name.demodulize, message: e.message },
      expires_in: FAILURE_TTL
    )
  end
end
