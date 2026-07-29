class AddDrawOrderToTournamentUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :tournament_users, :draw_order, :integer
  end
end
