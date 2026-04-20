class AddPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    # Index sur matches pour les requêtes filtrées par user_id et ordonnées par created_at
    add_index :matches, [:user_id, :created_at], name: 'index_matches_on_user_id_created_at'

    # Index sur avis pour les requêtes filtrées par reviewed_user_id et ordonnées par created_at
    add_index :avis, [:reviewed_user_id, :created_at], name: 'index_avis_on_reviewed_user_id_created_at'

    # Index sur match_users pour les requêtes filtrées par match_id et status
    add_index :match_users, [:match_id, :status], name: 'index_match_users_on_match_id_status'
  end
end
