class AddPoolToTournamentUsers < ActiveRecord::Migration[8.1]
  # Rattache un joueur à sa poule (format "poules", Lot 5). Index 0-based, nullable
  # (renseigné au lancement pour ce seul format).
  def change
    add_column :tournament_users, :pool, :integer
    add_index :tournament_users, %i[tournament_id pool]
  end
end
