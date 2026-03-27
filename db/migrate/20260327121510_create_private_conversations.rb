class CreatePrivateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :private_conversations do |t|
      # sender = l'initiateur de la conversation
      t.bigint :sender_id, null: false
      # recipient = le destinataire
      t.bigint :recipient_id, null: false
      # Timestamps de lecture pour gérer les badges non-lus
      t.datetime :sender_last_read_at
      t.datetime :recipient_last_read_at

      t.timestamps
    end

    # Un seul échange possible entre deux utilisateurs (quelque soit le sens)
    add_index :private_conversations, [:sender_id, :recipient_id], unique: true

    # Clés étrangères vers la table users
    add_foreign_key :private_conversations, :users, column: :sender_id
    add_foreign_key :private_conversations, :users, column: :recipient_id
  end
end
