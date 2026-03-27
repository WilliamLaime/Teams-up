class AddPrivateConversationIdToMessages < ActiveRecord::Migration[8.1]
  def change
    # Ajoute la référence à la conversation privée (nullable : un message
    # appartient soit à un match, soit à une conversation privée, pas les deux)
    add_column :messages, :private_conversation_id, :bigint
    add_index :messages, :private_conversation_id
    add_foreign_key :messages, :private_conversations

    # Rend match_id optionnel (était null: false implicitement)
    # Maintenant un message peut n'avoir que private_conversation_id
    change_column_null :messages, :match_id, true
  end
end
