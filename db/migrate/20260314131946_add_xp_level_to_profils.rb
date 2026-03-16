class AddXpLevelToProfils < ActiveRecord::Migration[8.1]
  def change
    # Niveau XP du joueur (1 à 10) — distinct du niveau de jeu ("Débutant" etc.)
    add_column :profils, :xp_level, :integer, default: 1, null: false
  end
end
