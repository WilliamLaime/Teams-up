class AddXpToProfils < ActiveRecord::Migration[8.1]
  def change
    # Colonne XP avec valeur par défaut 0, jamais nulle
    add_column :profils, :xp, :integer, default: 0, null: false
  end
end
