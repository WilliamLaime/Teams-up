# Bilan de parcours d'un joueur dans un tournoi (Lot 3).
# Stocké (et non calculé à la volée) pour grouper rapidement les joueurs par nombre
# de victoires à chaque tirage. La cohérence est garantie par un recompute
# déterministe depuis les matchs (voir SwissPairing#next_round!).
class AddSwissStatsToTournamentUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :tournament_users, :losses, :integer, null: false, default: 0
    add_column :tournament_users, :seed,   :integer # tête de série à l'entrée en bracket
    add_column :tournament_users, :state,  :string, null: false, default: "active" # "active" | "qualified" | "eliminated"
    add_column :tournament_users, :wins,   :integer, null: false, default: 0
  end
end
