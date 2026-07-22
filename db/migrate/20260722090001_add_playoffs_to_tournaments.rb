class AddPlayoffsToTournaments < ActiveRecord::Migration[8.1]
  # Lot 6 : le format "championnat" peut se jouer avec tableau final (comportement
  # historique, valeur par défaut) ou en championnat pur, où le vainqueur est le 1er
  # du classement après la dernière journée. Sans effet sur les autres formats.
  def change
    add_column :tournaments, :playoffs, :boolean, default: true, null: false
  end
end
