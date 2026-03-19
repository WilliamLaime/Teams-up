class FixLocalisationToString < ActiveRecord::Migration[8.1]
  def up
    # La colonne était en decimal, ce qui convertissait "Bordeaux" en 0.0
    # On la repasse en string pour stocker correctement les noms de villes
    change_column :profils, :localisation, :string
  end

  def down
    change_column :profils, :localisation, :decimal
  end
end
