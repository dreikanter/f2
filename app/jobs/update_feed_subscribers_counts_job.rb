class UpdateFeedSubscribersCountsJob < ApplicationJob
  queue_as :default

  def perform
    read_unrecorded_scopes

    countable_feeds
      .where(access_token: AccessToken.allowing_scope(AccessToken::READ_USERS_INFO_SCOPE))
      .find_each { |feed| UpdateFeedSubscribersCountJob.perform_later(feed) }
  end

  private

  # Feeds on a token without read-users-info are left out: the per-feed job
  # would only skip them, so enqueuing is pure overhead.
  def countable_feeds
    Feed.enabled.where.not(target_group: [nil, ""])
  end

  # Tokens validated before Feeder recorded scopes carry none, and the gate
  # above can't tell that from a token that isn't allowed — so those feeds
  # would sit out every run from here on. Reading the scopes once settles it,
  # and tomorrow's run acts on the answer.
  def read_unrecorded_scopes
    AccessToken.active
               .without_recorded_scopes
               .where(id: countable_feeds.select(:access_token_id))
               .find_each { |access_token| TokenScopesRefreshJob.perform_later(access_token) }
  end
end
