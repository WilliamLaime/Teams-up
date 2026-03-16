class AddSportToMatchesAndUsers < ActiveRecord::Migration[8.1]
  def change
    # Ajoute le sport associé à chaque match (nullable : les matchs existants n'ont pas de sport)
    add_reference :matches, :sport, null: true, foreign_key: true

    # Ajoute le sport actif de l'utilisateur (nullable : l'utilisateur peut n'en avoir aucun)
    add_column :users, :current_sport_id, :bigint, null: true
  end
end
