class AddCoverPositionToTeams < ActiveRecord::Migration[8.1]
  def change
    # "50% 50%" = centré par défaut (valeur CSS object-position)
    add_column :teams, :cover_position, :string, default: "50% 50%"
  end
end
