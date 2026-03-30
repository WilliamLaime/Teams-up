class AddUniqueIndexToVenuesNameCity < ActiveRecord::Migration[8.1]
  def change
    # Ajoute une colonne pour marquer les venues créées par les users via Nominatim.
    # Les venues de l'import initial (328k) restent avec from_nominatim = false.
    # Cela permet d'identifier les venues ajoutées dynamiquement par les users.
    add_column :venues, :from_nominatim, :boolean, default: false, null: false
  end
end
