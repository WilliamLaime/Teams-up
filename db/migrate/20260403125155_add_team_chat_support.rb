class AddTeamChatSupport < ActiveRecord::Migration[8.1]
  def change
    # Ajoute la référence vers l'équipe dans les messages
    # (un message peut appartenir à un match, une conversation privée OU une équipe)
    add_column :messages, :team_id, :bigint
    add_index  :messages, :team_id
    add_foreign_key :messages, :teams

    # Ajoute le suivi de lecture du chat d'équipe dans team_members
    # (même principe que last_read_at dans match_users)
    add_column :team_members, :chat_last_read_at, :datetime
  end
end
