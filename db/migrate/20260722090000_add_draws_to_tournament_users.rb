class AddDrawsToTournamentUsers < ActiveRecord::Migration[8.1]
  # Nuls (Lot 6) : sports collectifs à barème V/N/D (football, handball). Reste à 0
  # pour les sports sans nul (raquette, basket, volley) — cf. RoundRobinStats.
  def change
    add_column :tournament_users, :draws, :integer, default: 0, null: false
  end
end
