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

ActiveRecord::Schema[8.1].define(version: 2026_03_14_140000) do
ActiveRecord::Schema[8.1].define(version: 2026_03_16_142407) do
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

  create_table "matches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.string "description"
    t.string "image"
    t.string "format"
    t.string "level"
    t.string "place"
    t.integer "player_left"
    t.integer "price_per_player", default: 0
    t.bigint "sport_id"
    t.time "time"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "validation_mode", default: "automatic"
    t.bigint "venue_id"
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
    t.datetime "created_at", null: false
    t.string "description"
    t.string "first_name"
    t.string "last_name"
    t.string "level"
    t.decimal "localisation"
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

  create_table "user_achievements", force: :cascade do |t|
    t.bigint "achievement_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["achievement_id"], name: "index_user_achievements_on_achievement_id"
    t.index ["user_id", "achievement_id"], name: "index_user_achievements_on_user_id_and_achievement_id", unique: true
    t.index ["user_id"], name: "index_user_achievements_on_user_id"
  create_table "sports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "icon"
    t.string "name"
    t.string "slug"
    t.datetime "updated_at", null: false
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
    t.datetime "created_at", null: false
    t.bigint "current_sport_id"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
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
  add_foreign_key "match_users", "matches"
  add_foreign_key "match_users", "users"
  add_foreign_key "matches", "sports"
  add_foreign_key "matches", "users"
  add_foreign_key "matches", "venues"
  add_foreign_key "messages", "matches"
  add_foreign_key "messages", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "profils", "users"
  add_foreign_key "user_achievements", "achievements"
  add_foreign_key "user_achievements", "users"
  add_foreign_key "user_sports", "sports"
  add_foreign_key "user_sports", "users"
end
