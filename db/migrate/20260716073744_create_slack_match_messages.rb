# Mémorise chaque carte Slack postée pour un match, afin de pouvoir la ré-éditer
# (chat.update) quand le match change de statut (À venir → En cours → Terminé).
# Un match peut être partagé dans plusieurs channels : une ligne par (match, channel).
class CreateSlackMatchMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :slack_match_messages do |t|
      t.references :match, null: false, foreign_key: true
      t.references :slack_workspace, null: false, foreign_key: true
      t.string :channel_id, null: false
      t.string :message_ts, null: false

      t.timestamps
    end

    # Un seul message suivi par channel et par match (le re-partage met à jour la ligne).
    add_index :slack_match_messages, %i[match_id channel_id], unique: true
  end
end
