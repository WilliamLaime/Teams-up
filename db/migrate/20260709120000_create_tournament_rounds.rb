# Rondes d'un tournoi (Lot 3 — Ronde Suisse + tableau final).
# Une ronde regroupe les appariements générés en une fois :
#   - phase "swiss"   : une ronde de ronde suisse (tirage intégral) ;
#   - phase "bracket" : un tour du tableau final à élimination directe.
class CreateTournamentRounds < ActiveRecord::Migration[8.1]
  def change
    create_table :tournament_rounds do |t|
      t.integer :number, null: false            # n° dans sa phase (1..N)
      t.string  :phase,  null: false            # "swiss" | "bracket"
      t.string  :status, null: false, default: "pending" # "pending" | "in_progress" | "completed"
      t.references :tournament, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    # Idempotence : on ne peut pas générer deux fois la même ronde d'un tournoi.
    add_index :tournament_rounds, %i[tournament_id phase number], unique: true
  end
end
