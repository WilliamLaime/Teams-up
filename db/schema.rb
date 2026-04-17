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

ActiveRecord::Schema[8.1].define(version: 2026_04_16_100000) do
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

  create_table "contact_messages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.boolean "lu", default: false, null: false
    t.text "message", null: false
    t.string "nom", null: false
    t.string "prenom", null: false
    t.string "sujet", null: false
    t.datetime "updated_at", null: false
  end

  create_table "friendships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "friend_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["friend_id"], name: "index_friendships_on_friend_id"
    t.index ["user_id", "friend_id"], name: "index_friendships_on_user_id_and_friend_id", unique: true
    t.index ["user_id"], name: "index_friendships_on_user_id"
  end

  create_table "image_moderations", force: :cascade do |t|
    t.string "attachment_name", null: false
    t.datetime "checked_at"
    t.datetime "created_at", null: false
    t.bigint "moderatable_id", null: false
    t.string "moderatable_type", null: false
    t.string "provider", default: "sightengine", null: false
    t.string "reason"
    t.decimal "score", precision: 5, scale: 4
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["checked_at"], name: "index_image_moderations_on_checked_at"
    t.index ["moderatable_type", "moderatable_id", "attachment_name"], name: "index_image_moderations_on_moderatable_and_attachment", unique: true
    t.index ["status"], name: "index_image_moderations_on_status"
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
    t.string "genre_restriction", default: "tous"
    t.bigint "homme_du_match_id"
    t.string "level"
    t.string "place"
    t.integer "player_left"
    t.integer "players_present"
    t.integer "price_per_player", default: 0
    t.string "private_token"
    t.bigint "sport_id"
    t.bigint "team_id"
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
    t.index ["team_id"], name: "index_matches_on_team_id"
    t.index ["user_id"], name: "index_matches_on_user_id"
    t.index ["venue_id"], name: "index_matches_on_venue_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "match_id"
    t.bigint "private_conversation_id"
    t.bigint "team_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["match_id"], name: "index_messages_on_match_id"
    t.index ["private_conversation_id"], name: "index_messages_on_private_conversation_id"
    t.index ["team_id"], name: "index_messages_on_team_id"
    t.index ["user_id"], name: "index_messages_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.integer "actor_id"
    t.datetime "created_at", null: false
    t.string "link"
    t.string "message"
    t.string "notif_type"
    t.boolean "read", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "private_conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "recipient_dismissed_at"
    t.bigint "recipient_id", null: false
    t.datetime "recipient_last_read_at"
    t.datetime "sender_dismissed_at"
    t.bigint "sender_id", null: false
    t.datetime "sender_last_read_at"
    t.datetime "updated_at", null: false
    t.index ["sender_id", "recipient_id"], name: "index_private_conversations_on_sender_id_and_recipient_id", unique: true
  end

  create_table "profil_favorite_venues", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "profil_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "venue_id", null: false
    t.index ["profil_id", "venue_id"], name: "index_profil_favorite_venues_on_profil_and_venue", unique: true
    t.index ["profil_id"], name: "index_profil_favorite_venues_on_profil_id"
    t.index ["venue_id"], name: "index_profil_favorite_venues_on_venue_id"
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
    t.boolean "light_mode", default: false, null: false
    t.string "localisation"
    t.datetime "onboarding_shown_at"
    t.string "phone"
    t.string "preferred_city"
    t.datetime "profile_reminder_dismissed_at"
    t.string "role"
    t.integer "stat_points", default: 0, null: false
    t.datetime "time_available"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "xp", default: 0, null: false
    t.integer "xp_level", default: 1, null: false
    t.index ["preferred_city"], name: "index_profils_on_preferred_city"
    t.index ["user_id"], name: "index_profils_on_user_id"
  end

  create_table "security_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "details", default: {}
    t.string "event_type", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id"
    t.index ["created_at"], name: "index_security_logs_on_created_at"
    t.index ["event_type"], name: "index_security_logs_on_event_type"
    t.index ["ip_address"], name: "index_security_logs_on_ip_address"
    t.index ["user_id"], name: "index_security_logs_on_user_id"
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

  create_table "team_invitations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "invitee_id", null: false
    t.bigint "inviter_id", null: false
    t.bigint "proposed_by_id"
    t.string "status", default: "pending", null: false
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["invitee_id"], name: "index_team_invitations_on_invitee_id"
    t.index ["inviter_id"], name: "index_team_invitations_on_inviter_id"
    t.index ["proposed_by_id"], name: "index_team_invitations_on_proposed_by_id"
    t.index ["team_id", "invitee_id"], name: "index_team_invitations_pending_unique", unique: true, where: "((status)::text = 'pending'::text)"
    t.index ["team_id"], name: "index_team_invitations_on_team_id"
  end

  create_table "team_members", force: :cascade do |t|
    t.datetime "chat_last_read_at"
    t.datetime "created_at", null: false
    t.datetime "joined_at"
    t.string "role", default: "member", null: false
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["team_id", "user_id"], name: "index_team_members_on_team_id_and_user_id", unique: true
    t.index ["team_id"], name: "index_team_members_on_team_id"
    t.index ["user_id"], name: "index_team_members_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.text "badge_svg"
    t.bigint "captain_id", null: false
    t.string "cover_position", default: "50% 50%"
    t.float "cover_zoom", default: 1.0
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["captain_id"], name: "index_teams_on_captain_id"
    t.index ["name", "captain_id"], name: "index_teams_on_name_and_captain_id", unique: true
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
    t.boolean "admin", default: false, null: false
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.bigint "current_sport_id"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "genre"
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
    t.boolean "from_nominatim", default: false, null: false
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
  add_foreign_key "friendships", "users"
  add_foreign_key "friendships", "users", column: "friend_id"
  add_foreign_key "match_users", "matches"
  add_foreign_key "match_users", "users"
  add_foreign_key "match_votes", "matches"
  add_foreign_key "match_votes", "users", column: "voted_for_id"
  add_foreign_key "match_votes", "users", column: "voter_id"
  add_foreign_key "matches", "sports"
  add_foreign_key "matches", "teams"
  add_foreign_key "matches", "users"
  add_foreign_key "matches", "users", column: "homme_du_match_id"
  add_foreign_key "matches", "venues"
  add_foreign_key "messages", "matches"
  add_foreign_key "messages", "private_conversations"
  add_foreign_key "messages", "teams"
  add_foreign_key "messages", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "private_conversations", "users", column: "recipient_id"
  add_foreign_key "private_conversations", "users", column: "sender_id"
  add_foreign_key "profil_favorite_venues", "profils"
  add_foreign_key "profil_favorite_venues", "venues"
  add_foreign_key "profils", "users"
  add_foreign_key "security_logs", "users", on_delete: :nullify
  add_foreign_key "sport_profils", "profils"
  add_foreign_key "sport_profils", "sports"
  add_foreign_key "team_invitations", "teams"
  add_foreign_key "team_invitations", "users", column: "invitee_id"
  add_foreign_key "team_invitations", "users", column: "inviter_id"
  add_foreign_key "team_invitations", "users", column: "proposed_by_id"
  add_foreign_key "team_members", "teams"
  add_foreign_key "team_members", "users"
  add_foreign_key "teams", "users", column: "captain_id"
  add_foreign_key "user_achievements", "achievements"
  add_foreign_key "user_achievements", "users"
  add_foreign_key "user_sports", "sports"
  add_foreign_key "user_sports", "users"
end
