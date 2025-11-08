# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.2].define(version: 2025_11_08_205732) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "access_token_details", force: :cascade do |t|
    t.bigint "access_token_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "expires_at", null: false
    t.datetime "updated_at", null: false
    t.index ["access_token_id"], name: "index_access_token_details_on_access_token_id", unique: true
    t.index ["expires_at"], name: "index_access_token_details_on_expires_at"
  end

  create_table "access_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_token"
    t.string "host", null: false
    t.datetime "last_used_at"
    t.string "name"
    t.string "owner"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "name"], name: "index_access_tokens_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_access_tokens_on_user_id"
  end

  create_table "events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.integer "level", default: 1, null: false
    t.text "message", default: "", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "subject_id"
    t.string "subject_type"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["expires_at"], name: "index_events_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["level", "created_at"], name: "index_events_on_level_and_created_at"
    t.index ["subject_type", "subject_id"], name: "index_events_on_subject_type_and_subject_id"
    t.index ["type", "created_at"], name: "index_events_on_type_and_created_at"
    t.index ["user_id"], name: "index_events_on_user_id"
  end

  create_table "feed_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "feed_id", null: false
    t.datetime "published_at"
    t.jsonb "raw_data"
    t.integer "status", default: 0
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["feed_id", "uid"], name: "index_feed_entries_on_feed_id_and_uid", unique: true
    t.index ["feed_id"], name: "index_feed_entries_on_feed_id"
  end

  create_table "feed_entry_uids", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "feed_id", null: false
    t.datetime "imported_at", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["feed_id", "uid"], name: "index_feed_entry_uids_on_feed_id_and_uid", unique: true
    t.index ["feed_id"], name: "index_feed_entry_uids_on_feed_id"
    t.index ["imported_at"], name: "index_feed_entry_uids_on_imported_at"
  end

  create_table "feed_metrics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.bigint "feed_id", null: false
    t.integer "invalid_posts_count", default: 0, null: false
    t.integer "posts_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_feed_metrics_on_date"
    t.index ["feed_id", "date"], name: "index_feed_metrics_on_feed_id_and_date", unique: true
  end

  create_table "feed_previews", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "data"
    t.string "feed_profile_key"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.bigint "user_id", null: false
    t.index ["created_at"], name: "index_feed_previews_on_created_at"
    t.index ["status"], name: "index_feed_previews_on_status"
    t.index ["user_id"], name: "index_feed_previews_on_user_id"
  end

  create_table "feed_schedules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "feed_id", null: false
    t.datetime "last_run_at"
    t.datetime "next_run_at"
    t.datetime "updated_at", null: false
    t.index ["feed_id"], name: "index_feed_schedules_on_feed_id"
  end

  create_table "feeds", force: :cascade do |t|
    t.bigint "access_token_id"
    t.datetime "created_at", null: false
    t.string "cron_expression"
    t.string "description", default: "", null: false
    t.string "feed_profile_key"
    t.datetime "import_after"
    t.string "name", null: false
    t.integer "state", default: 0, null: false
    t.string "target_group", limit: 80
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.bigint "user_id", null: false
    t.index ["access_token_id"], name: "index_feeds_on_access_token_id"
    t.index ["user_id"], name: "index_feeds_on_user_id"
  end

  create_table "invites", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id", null: false
    t.bigint "invited_user_id"
    t.datetime "updated_at", null: false
    t.index ["created_by_user_id"], name: "index_invites_on_created_by_user_id"
    t.index ["invited_user_id"], name: "index_invites_on_invited_user_id"
  end

  create_table "permissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_permissions_on_user_id"
  end

  create_table "posts", force: :cascade do |t|
    t.text "attachment_urls", default: [], null: false, array: true
    t.text "comments", default: [], null: false, array: true
    t.text "content", default: "", null: false
    t.datetime "created_at", null: false
    t.bigint "feed_entry_id", null: false
    t.bigint "feed_id", null: false
    t.string "freefeed_post_id"
    t.datetime "published_at", null: false
    t.string "source_url", null: false
    t.integer "status", default: 0, null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.text "validation_errors", default: [], null: false, array: true
    t.index ["feed_entry_id"], name: "index_posts_on_feed_entry_id"
    t.index ["feed_id", "uid"], name: "index_posts_on_feed_id_and_uid", unique: true
    t.index ["feed_id"], name: "index_posts_on_feed_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.integer "available_invites", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.datetime "email_deactivated_at"
    t.string "email_deactivation_reason"
    t.string "name", default: "", null: false
    t.string "password_digest", null: false
    t.datetime "password_updated_at", precision: nil, null: false
    t.integer "state", default: 0, null: false
    t.datetime "suspended_at"
    t.string "unconfirmed_email"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["email_deactivated_at"], name: "index_users_on_email_deactivated_at"
    t.index ["state"], name: "index_users_on_state"
  end

  add_foreign_key "access_token_details", "access_tokens"
  add_foreign_key "access_tokens", "users"
  add_foreign_key "events", "users"
  add_foreign_key "feed_entries", "feeds"
  add_foreign_key "feed_entry_uids", "feeds", on_delete: :cascade
  add_foreign_key "feed_metrics", "feeds", on_delete: :cascade
  add_foreign_key "feed_previews", "users"
  add_foreign_key "feed_schedules", "feeds"
  add_foreign_key "feeds", "access_tokens"
  add_foreign_key "feeds", "users"
  add_foreign_key "invites", "users", column: "created_by_user_id"
  add_foreign_key "invites", "users", column: "invited_user_id"
  add_foreign_key "permissions", "users"
  add_foreign_key "posts", "feed_entries"
  add_foreign_key "posts", "feeds"
  add_foreign_key "sessions", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
