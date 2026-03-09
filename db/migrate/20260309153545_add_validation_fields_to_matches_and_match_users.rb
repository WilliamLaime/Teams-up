class AddValidationFieldsToMatchesAndMatchUsers < ActiveRecord::Migration[8.1]
  def change
    # Ajoute le mode de validation sur le match :
    # 'automatic' = le joueur est accepté immédiatement
    # 'manual'    = l'organisateur doit valider manuellement
    add_column :matches, :validation_mode, :string, default: "automatic"

    # Ajoute le statut de l'inscription d'un joueur :
    # 'pending'  = en attente de validation
    # 'approved' = accepté
    # 'rejected' = refusé
    add_column :match_users, :status, :string, default: "pending"
  end
end
