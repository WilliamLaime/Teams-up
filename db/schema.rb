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

ActiveRecord::Schema[8.1].define(version: 2026_03_24_133459) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "achievements", force: :cascade do |t|
    t.string "category", default: "match"
    t.datetime "created_at", null: false
    t.string "description"
    t.string "icon_emoji"
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "xp_reward", default: 0, null: false
    t.index ["key"], name: "index_achievements_on_key", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "avis", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "match_id", null: false
    t.integer "rating", null: false
    t.bigint "reviewed_user_id", null: false
    t.bigint "reviewer_id", null: false
    t.datetime "updated_at", null: false
    t.index ["match_id"], name: "index_avis_on_match_id"
    t.index ["reviewed_user_id"], name: "index_avis_on_reviewed_user_id"
    t.index ["reviewer_id", "reviewed_user_id", "match_id"], name: "index_avis_on_reviewer_id_and_reviewed_user_id_and_match_id", unique: true
    t.index ["reviewer_id"], name: "index_avis_on_reviewer_id"
  end

  create_table "match_users", force: :cascade do |t|
    t.datetime "chat_dismissed_at"
    t.datetime "created_at", null: false
    t.datetime "last_read_at"
    t.bigint "match_id", null: false
    t.text "message"
    t.string "role"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["match_id"], name: "index_match_users_on_match_id"
    t.index ["user_id"], name: "index_match_users_on_user_id"
  end

  create_table "match_votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "match_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "voted_for_id", null: false
    t.bigint "voter_id", null: false
    t.index ["match_id"], name: "index_match_votes_on_match_id"
    t.index ["voted_for_id"], name: "index_match_votes_on_voted_for_id"
    t.index ["voter_id", "match_id"], name: "index_match_votes_on_voter_id_and_match_id", unique: true
    t.index ["voter_id"], name: "index_match_votes_on_voter_id"
  end

  create_table "matches", force: :cascade do |t|
    t.string "banner_image"
    t.datetime "created_at", null: false
    t.date "date"
    t.string "description"
    t.string "format"
    t.bigint "homme_du_match_id"
    t.string "level"
    t.integer "max_supporters", default: 0
    t.string "place"
    t.integer "player_left"
    t.integer "price_per_player", default: 0
    t.string "private_token"
    t.bigint "sport_id"
    t.time "time"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "validation_mode", default: "automatic"
    t.bigint "venue_id"
    t.string "visibility", default: "public", null: false
    t.index ["homme_du_match_id"], name: "index_matches_on_homme_du_match_id"
    t.index ["private_token"], name: "index_matches_on_private_token", unique: true
    t.index ["sport_id"], name: "index_matches_on_sport_id"
    t.index ["user_id"], name: "index_matches_on_user_id"
    t.index ["venue_id"], name: "index_matches_on_venue_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "match_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["match_id"], name: "index_messages_on_match_id"
    t.index ["user_id"], name: "index_messages_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "link"
    t.string "message"
    t.boolean "read", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "profils", force: :cascade do |t|
    t.string "address"
    t.integer "attr_attack", default: 0, null: false
    t.integer "attr_defense", default: 0, null: false
    t.integer "attr_endurance", default: 0, null: false
    t.integer "attr_mental", default: 0, null: false
    t.integer "attr_precision", default: 0, null: false
    t.integer "attr_speed", default: 0, null: false
    t.integer "attr_tactics", default: 0, null: false
    t.integer "attr_teamwork", default: 0, null: false
    t.float "average_rating", default: 0.0
    t.integer "avis_count", default: 0
    t.datetime "created_at", null: false
    t.string "description"
    t.string "first_name"
    t.integer "homme_du_match_count", default: 0, null: false
    t.string "last_name"
    t.string "level"
    t.string "localisation"
    t.string "phone"
    t.string "role"
    t.integer "stat_points", default: 0, null: false
    t.datetime "time_available"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "xp", default: 0, null: false
    t.integer "xp_level", default: 1, null: false
    t.index ["user_id"], name: "index_profils_on_user_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
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

  create_table "sport_profils", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "level"
    t.bigint "profil_id", null: false
    t.string "role"
    t.bigint "sport_id", null: false
    t.datetime "updated_at", null: false
    t.index ["profil_id", "sport_id"], name: "index_sport_profils_on_profil_id_and_sport_id", unique: true
    t.index ["profil_id"], name: "index_sport_profils_on_profil_id"
    t.index ["sport_id"], name: "index_sport_profils_on_sport_id"
  end

  create_table "sports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "icon"
    t.string "name"
    t.string "slug"
    t.datetime "updated_at", null: false
  end

  create_table "user_achievements", force: :cascade do |t|
    t.bigint "achievement_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["achievement_id"], name: "index_user_achievements_on_achievement_id"
    t.index ["user_id", "achievement_id"], name: "index_user_achievements_on_user_id_and_achievement_id", unique: true
    t.index ["user_id"], name: "index_user_achievements_on_user_id"
  end

  create_table "user_sports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "sport_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["sport_id"], name: "index_user_sports_on_sport_id"
    t.index ["user_id"], name: "index_user_sports_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.bigint "current_sport_id"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "uid"
    t.string "unconfirmed_email"
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "venues", force: :cascade do |t|
    t.string "address"
    t.string "city"
    t.datetime "created_at", null: false
    t.float "latitude"
    t.float "longitude"
    t.string "name"
    t.string "postal_code"
    t.string "sport_type"
    t.datetime "updated_at", null: false
    t.index ["city"], name: "index_venues_on_city"
    t.index ["sport_type"], name: "index_venues_on_sport_type"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "avis", "matches"
  add_foreign_key "avis", "users", column: "reviewed_user_id"
  add_foreign_key "avis", "users", column: "reviewer_id"
  add_foreign_key "match_users", "matches"
  add_foreign_key "match_users", "users"
  add_foreign_key "match_votes", "matches"
  add_foreign_key "match_votes", "users", column: "voted_for_id"
  add_foreign_key "match_votes", "users", column: "voter_id"
  add_foreign_key "matches", "sports"
  add_foreign_key "matches", "users"
  add_foreign_key "matches", "users", column: "homme_du_match_id"
  add_foreign_key "matches", "venues"
  add_foreign_key "messages", "matches"
  add_foreign_key "messages", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "profils", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "sport_profils", "profils"
  add_foreign_key "sport_profils", "sports"
  add_foreign_key "user_achievements", "achievements"
  add_foreign_key "user_achievements", "users"
  add_foreign_key "user_sports", "sports"
  add_foreign_key "user_sports", "users"
end
