class AddForfeitToTournamentMatches < ActiveRecord::Migration[8.1]
  # Abandon / forfait (Lot 5) : `forfeit` marque une victoire par forfait, et
  # `retired_player_id` désigne le joueur (tournament_user) qui a abandonné.
  def change
    add_column :tournament_matches, :forfeit, :boolean, null: false, default: false
    add_reference :tournament_matches, :retired_player,
                  null: true, foreign_key: { to_table: :tournament_users }
  end
end
