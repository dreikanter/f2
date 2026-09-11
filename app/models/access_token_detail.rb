class AccessTokenDetail < ApplicationRecord
  include HasOperationRuns
  include PolledRun

  # Superseded by the dedicated columns below; kept in the schema so old-code
  # containers survive the deploy that ships this model. A follow-up migration
  # drops it once this code is live everywhere.
  self.ignored_columns += ["data"]

  belongs_to :access_token

  # Recover if the scheduled timeout is lost or fails to settle the run.
  GROUPS_REFRESH_STALE_AFTER = 15.minutes

  def group_names
    managed_groups.map { |group| group["username"] }.compact
  end

  def groups_refresh_running?
    active_operation_run(:groups_refresh)&.in_progress?(stale_after: GROUPS_REFRESH_STALE_AFTER) || false
  end

  def groups_refresh_failed?
    run = latest_operation_run(:groups_refresh)
    return false unless run

    run.status.in?(%w[failed timed_out]) && run.finished_at.present? && run.finished_at >= updated_at
  end

  # @return [AccessTokenDetail] self, persisted with a new run
  def start_groups_refresh!
    save! unless persisted?
    run = OperationRun.start!(
      subject: self,
      kind: :groups_refresh,
      timeout: TIMEOUT_AFTER
    )
    TokenGroupsRefreshJob.perform_later(run)
    TokenGroupsRefreshTimeoutJob
      .set(wait_until: run.deadline_at)
      .perform_later(run)
    self
  end

  # @param groups [Array<Hash>] fetched FreeFeed groups
  # @return [AccessTokenDetail] updated detail
  def replace_managed_groups!(groups)
    update!(managed_groups: groups.map { |group| group.deep_stringify_keys })
    self
  end

  # Validation also fetches groups, so it can finish a refresh that is waiting
  # for the same result.
  # @param groups [Array<Hash>] fetched FreeFeed groups
  # @return [AccessTokenDetail] updated detail
  def replace_managed_groups_and_finish_refresh!(groups)
    run = active_operation_run(:groups_refresh)
    return replace_managed_groups!(groups) unless run

    run.succeed! { |detail| detail.replace_managed_groups!(groups) }
    self
  end
end
