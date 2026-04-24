class AddNullifyToMessagesUserFk < ActiveRecord::Migration[8.1]
  def change
    # Modifie la FK messages.user_id pour utiliser on_delete: :nullify
    # Permet aux messages de rester en BDD après la suppression d'un user (RGPD art. 17)
    remove_foreign_key :messages, :users
    add_foreign_key :messages, :users, on_delete: :nullify
  end
end
