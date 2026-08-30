class AccessTokenDetail < ApplicationRecord
  # Superseded by the dedicated columns below; kept in the schema so old-code
  # containers survive the deploy that ships this model. A follow-up migration
  # drops it once this code is live everywhere.
  self.ignored_columns += ["data"]

  belongs_to :access_token

  GROUPS_REFRESH_POLLING_INTERVAL_MS = 2500
  GROUPS_REFRESH_TIMEOUT_AFTER = 85.seconds

  enum :groups_refresh_state, { running: 0, failed: 1 }, prefix: :groups_refresh

  def group_names
    managed_groups.map { |group| group["username"] }.compact
  end

  def groups_refresh_running?(run_id: nil)
    super() &&
      groups_refresh_requested_at.present? &&
      groups_refresh_run_id.present? &&
      (run_id.nil? || groups_refresh_run_id == run_id)
  end

  # @return [AccessTokenDetail] self, persisted with a new run
  def start_groups_refresh!
    requested_at = Time.current
    run_id = SecureRandom.uuid
    update!(
      groups_refresh_state: :running,
      groups_refresh_requested_at: requested_at,
      groups_refresh_run_id: run_id
    )
    TokenGroupsRefreshJob.perform_later(access_token, run_id)
    TokenGroupsRefreshTimeoutJob
      .set(wait_until: requested_at + GROUPS_REFRESH_TIMEOUT_AFTER)
      .perform_later(id, run_id)
    self
  end

  # Keys are stringified up front so readers in the same process see the shape
  # a jsonb round-trip would produce.
  # @param groups [Array<Hash>] fetched FreeFeed groups
  # @param run_id [String] run token captured by the worker
  # @return [Boolean] whether the matching run was settled
  def complete_groups_refresh!(groups, run_id:)
    updated = matching_groups_refresh(run_id).update_all(
      managed_groups: groups.map { |group| group.deep_stringify_keys },
      groups_refresh_state: nil,
      groups_refresh_requested_at: nil,
      groups_refresh_run_id: nil,
      updated_at: Time.current
    )
    reload if updated.positive?
    updated.positive?
  end

  # @param run_id [String] run token captured by the worker
  # @return [Boolean] whether the matching run was settled
  def fail_groups_refresh!(run_id:)
    updated = matching_groups_refresh(run_id).update_all(
      groups_refresh_state: :failed,
      groups_refresh_requested_at: Time.current,
      groups_refresh_run_id: nil,
      updated_at: Time.current
    )
    reload if updated.positive?
    updated.positive?
  end

  # @param run_id [String] run token captured by the timeout job
  # @return [AccessTokenDetail] self
  def timeout_groups_refresh!(run_id:)
    updated = matching_groups_refresh(run_id).update_all(
      groups_refresh_state: :failed,
      groups_refresh_requested_at: Time.current,
      groups_refresh_run_id: SecureRandom.uuid,
      updated_at: Time.current
    )
    reload if updated.positive?
    self
  end

  def self.groups_refresh_polling_max_polls
    # The first poll is immediate. Two extra polls leave one interval for Solid
    # Queue to dispatch a due timeout and let the final poll render its result.
    GROUPS_REFRESH_TIMEOUT_AFTER.in_milliseconds.div(GROUPS_REFRESH_POLLING_INTERVAL_MS) + 2
  end

  private

  def matching_groups_refresh(run_id)
    self.class.where(id: id, groups_refresh_state: :running, groups_refresh_run_id: run_id)
  end
end
