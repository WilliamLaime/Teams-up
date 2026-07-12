# Matchs d'un tournoi (Lot 3). Un match oppose exactement 2 joueurs :
# deux FK player_a / player_b vers tournament_users (l'inscription, pas l'user global,
# pour rattacher le bilan V/D à la participation). player_b nul = bye (exempt).
# Au Lot 3 on ne stocke que le vainqueur (V/D) ; le score set-par-set arrive au Lot 4.
class CreateTournamentMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :tournament_matches do |t|
      t.boolean :is_bye, null: false, default: false      # true = exempt (victoire auto de player_a)
      t.bigint  :player_a_id                              # tournament_user
      t.bigint  :player_b_id                              # tournament_user (nul si bye)
      t.integer :position, null: false                    # ordre d'affichage / slot bracket (0-based)
      t.string  :status, null: false, default: "pending"  # "pending" | "completed"
      t.references :tournament_round, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :winner_id # tournament_user gagnant

      t.timestamps
    end

    add_index :tournament_matches, :player_a_id
    add_index :tournament_matches, :player_b_id
    add_index :tournament_matches, :winner_id
    add_index :tournament_matches, %i[tournament_round_id position], unique: true

    add_foreign_key :tournament_matches, :tournament_users, column: :player_a_id
    add_foreign_key :tournament_matches, :tournament_users, column: :player_b_id
    add_foreign_key :tournament_matches, :tournament_users, column: :winner_id
  end
end
