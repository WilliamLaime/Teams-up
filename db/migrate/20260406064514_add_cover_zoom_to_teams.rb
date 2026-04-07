class AddCoverZoomToTeams < ActiveRecord::Migration[8.1]
  def change
    add_column :teams, :cover_zoom, :float, default: 1.0
  end
end
