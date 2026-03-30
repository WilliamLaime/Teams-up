class CreateProfilFavoriteVenues < ActiveRecord::Migration[7.0]
  def change
    # Crée la table de jointure entre Profils et Venues
    # Permet à un utilisateur de favoritiser ses lieux préférés pour jouer
    create_table :profil_favorite_venues do |t|
      # Référence au profil (clé étrangère)
      t.references :profil, null: false, foreign_key: true

      # Référence au lieu/établissement (clé étrangère)
      t.references :venue, null: false, foreign_key: true

      # Timestamps de création/mise à jour
      t.timestamps
    end

    # Index composite unique : empêche les doublons
    # Un profil ne peut pas ajouter le même lieu deux fois
    add_index :profil_favorite_venues,
              [:profil_id, :venue_id],
              unique: true,
              name: "index_profil_favorite_venues_on_profil_and_venue"
  end
end
