class CreateSportProfils < ActiveRecord::Migration[8.1]
  def change
    create_table :sport_profils do |t|
      # Lien vers le profil de l'utilisateur
      t.references :profil, null: false, foreign_key: true
      # Lien vers le sport concerné
      t.references :sport, null: false, foreign_key: true
      # Niveau de jeu pour ce sport : "Débutant", "Intermédiaire", "Avancé"
      t.string :level
      # Rôle préféré pour ce sport (ex: Attaquant, Gardien...)
      t.string :role

      t.timestamps
    end

    # Un profil ne peut avoir qu'un seul SportProfil par sport
    add_index :sport_profils, [:profil_id, :sport_id], unique: true
  end
end
