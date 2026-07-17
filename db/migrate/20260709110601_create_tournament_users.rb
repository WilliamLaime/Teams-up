# Table de jointure participants ↔ tournoi (inscriptions).
# Équivalent de `match_users` pour les tournois. Volontairement minimale au Lot 1 :
# la validation manuelle / file d'attente / paiement viendront plus tard.
class CreateTournamentUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :tournament_users do |t|
      t.references :tournament, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role                          # "joueur" | "admin"
      t.string :status, default: "approved"   # "approved" | "pending"

      t.timestamps
    end

    # Un utilisateur ne peut s'inscrire qu'une fois au même tournoi.
    add_index :tournament_users, [:tournament_id, :user_id], unique: true
  end
end
