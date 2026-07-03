class AddChatAndNotificationIndexes < ActiveRecord::Migration[8.1]
  # Index préventifs pour la montée en charge (sidebar chat + cloche de notifs
  # sont sollicitées sur CHAQUE page authentifiée).
  def change
    # Cloche de notifications : current_user.notifications.unread.count sur chaque page,
    # et notifications#index trie par (read, created_at).
    add_index :notifications, [:user_id, :read, :created_at],
              name: "index_notifications_on_user_id_read_created_at",
              if_not_exists: true

    # actor_id (auteur de la notif) : belongs_to sans index jusqu'ici.
    add_index :notifications, :actor_id,
              name: "index_notifications_on_actor_id",
              if_not_exists: true

    # match_users filtrés par (user_id, status) : très fréquent (profils, conversations,
    # application_controller). L'index existant est (match_id, status), pas (user_id, status).
    add_index :match_users, [:user_id, :status],
              name: "index_match_users_on_user_id_status",
              if_not_exists: true

    # Dernier message par conversation (messages.last / where(created_at > ?)) :
    # index composites (contexte, created_at) pour servir le tri chronologique.
    add_index :messages, [:match_id, :created_at],
              name: "index_messages_on_match_id_created_at",
              if_not_exists: true
    add_index :messages, [:team_id, :created_at],
              name: "index_messages_on_team_id_created_at",
              if_not_exists: true
    add_index :messages, [:private_conversation_id, :created_at],
              name: "index_messages_on_private_conversation_id_created_at",
              if_not_exists: true
  end
end
