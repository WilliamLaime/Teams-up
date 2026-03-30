class AddPreferredCityToProfils < ActiveRecord::Migration[7.0]
  def change
    # Ajoute un champ pour la ville préférée du joueur
    # Utilisé pour pré-filtrer automatiquement les matchs proposés
    add_column :profils, :preferred_city, :string

    # Ajoute un index pour les recherches futures (optionnel)
    add_index :profils, :preferred_city
  end
end
