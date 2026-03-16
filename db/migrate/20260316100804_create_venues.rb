class CreateVenues < ActiveRecord::Migration[8.1]
  def change
    create_table :venues do |t|
      t.string :name        # Nom de l'installation sportive
      t.string :sport_type  # Type d'équipement sportif (ex: "Court de tennis")
      t.string :city        # Commune
      t.string :address     # Adresse
      t.string :postal_code # Code postal
      t.float :longitude    # Longitude GPS
      t.float :latitude     # Latitude GPS

      t.timestamps
    end

    # Index pour accélérer les recherches par ville et type de sport
    add_index :venues, :city
    add_index :venues, :sport_type
  end
end
