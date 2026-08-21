class AccessTokenDetail < ApplicationRecord
  # Superseded by the dedicated columns below; kept in the schema so old-code
  # containers survive the deploy that ships this model. A follow-up migration
  # drops it once this code is live everywhere.
  self.ignored_columns += ["data"]

  belongs_to :access_token

  # A refresh started longer ago than this is treated as abandoned (the job
  # died without settling), so a new refresh can start and pages don't render
  # a perpetual in-progress state.
  GROUPS_REFRESH_STALE_AFTER = 15.minutes

  def group_names
    managed_groups.map { |group| group["username"] }.compact
  end

  def groups_refresh_running?
    groups_refresh_state == "running" &&
      groups_refresh_requested_at.present? &&
      groups_refresh_requested_at > GROUPS_REFRESH_STALE_AFTER.ago
  end

  def groups_refresh_failed?
    groups_refresh_state == "failed"
  end

  def begin_groups_refresh!
    update!(groups_refresh_state: "running", groups_refresh_requested_at: Time.current)
  end

  # Keys are stringified up front so readers in the same process see the shape
  # a jsonb round-trip would produce.
  def complete_groups_refresh!(groups)
    update!(
      managed_groups: groups.map { |group| group.deep_stringify_keys },
      groups_refresh_state: nil,
      groups_refresh_requested_at: nil
    )
  end

  def fail_groups_refresh!
    update!(groups_refresh_state: "failed", groups_refresh_requested_at: Time.current)
  end
end
