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

  # Returns the new marker's id; the settle calls take it back so a job can
  # only settle the refresh it was enqueued for. A delayed job can outlive its
  # marker's staleness window, and without the id check it would clear or fail
  # the marker of a newer refresh that is still running.
  def begin_groups_refresh!
    refresh_id = SecureRandom.hex(8)
    marker = { "id" => refresh_id, "state" => "running", "requested_at" => Time.current.iso8601 }
    update_data! { |data| data.merge("groups_refresh" => marker) }
    refresh_id
  end

  # Keys are stringified up front so readers in the same process see the shape
  # a jsonb round-trip would produce. The fetched groups are stored even when a
  # newer refresh owns the marker — they're fresh, and the newer job will
  # overwrite them when it settles.
  def complete_groups_refresh!(groups, refresh_id = nil)
    stored = groups.map { |group| group.deep_stringify_keys }
    update_data! do |data|
      merged = data.merge("managed_groups" => stored)
      settles_current_refresh?(merged, refresh_id) ? merged.except("groups_refresh") : merged
    end
  end

  def fail_groups_refresh!(refresh_id = nil)
    update_data! do |data|
      next data unless settles_current_refresh?(data, refresh_id)

      data.merge("groups_refresh" => { "id" => refresh_id, "state" => "failed", "requested_at" => Time.current.iso8601 }.compact)
    end
  end

  private

  # A nil refresh_id settles unconditionally (trusted, non-job callers); a
  # given id only settles the marker it created.
  def settles_current_refresh?(data, refresh_id)
    refresh_id.nil? || data.dig("groups_refresh", "id") == refresh_id
  end

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
