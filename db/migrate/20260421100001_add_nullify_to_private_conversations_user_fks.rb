class AddNullifyToPrivateConversationsUserFks < ActiveRecord::Migration[8.1]
  def change
    # Modifie les FK private_conversations.sender_id et recipient_id
    # pour utiliser on_delete: :nullify (RGPD art. 17)
    # Permet aux conversations privées de rester en BDD après suppression d'un user

    remove_foreign_key :private_conversations, column: :sender_id
    remove_foreign_key :private_conversations, column: :recipient_id

    add_foreign_key :private_conversations, :users, column: :sender_id, on_delete: :nullify
    add_foreign_key :private_conversations, :users, column: :recipient_id, on_delete: :nullify
  end
end
