class AccessTokenDetail < ApplicationRecord
  belongs_to :access_token

  validates :data, presence: true

  # A refresh marker older than this is treated as abandoned (the job died
  # without settling), so a new refresh can start and pages don't render a
  # perpetual in-progress state.
  GROUPS_REFRESH_STALE_AFTER = 15.minutes

  def user_info
    (data && data["user_info"]) || {}
  end

  def managed_groups
    (data && data["managed_groups"]) || []
  end

  def group_names
    managed_groups.map { |group| group["username"] }.compact
  end

  def groups_refresh_running?
    groups_refresh["state"] == "running" && !groups_refresh_stale?
  end

  def groups_refresh_failed?
    groups_refresh["state"] == "failed"
  end

  def begin_groups_refresh!
    update_data! { |data| data.merge("groups_refresh" => { "state" => "running", "requested_at" => Time.current.iso8601 }) }
  end

  # Keys are stringified up front so readers in the same process see the shape
  # a jsonb round-trip would produce.
  def complete_groups_refresh!(groups)
    stored = groups.map { |group| group.deep_stringify_keys }
    update_data! { |data| data.merge("managed_groups" => stored).except("groups_refresh") }
  end

  def fail_groups_refresh!
    update_data! { |data| data.merge("groups_refresh" => { "state" => "failed", "requested_at" => Time.current.iso8601 }) }
  end

  private

  def groups_refresh
    (data && data["groups_refresh"]) || {}
  end

  def groups_refresh_stale?
    requested_at = Time.zone.parse(groups_refresh["requested_at"].to_s)
    requested_at.nil? || requested_at < GROUPS_REFRESH_STALE_AFTER.ago
  rescue ArgumentError
    true
  end

  # The refresh marker and the groups list live in the same jsonb column that
  # the validation service also rewrites, so mutate it under a row lock to keep
  # concurrent writers from clobbering each other's keys.
  def update_data!(&block)
    if persisted?
      with_lock { update!(data: block.call(data || {})) }
    else
      update!(data: block.call(data || {}))
    end
  end
end
