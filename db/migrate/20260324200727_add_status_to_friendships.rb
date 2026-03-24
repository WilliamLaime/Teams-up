class AddStatusToFriendships < ActiveRecord::Migration[8.1]
  def change
    # Ajoute le statut de la demande d'ami
    # "pending"  → demande envoyée, en attente de réponse
    # "accepted" → demande acceptée, les deux sont amis
    # "declined" → demande refusée
    add_column :friendships, :status, :string, default: "pending", null: false
  end
end
