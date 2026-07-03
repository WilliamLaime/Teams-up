class AddPerformanceIndexesToMatchUsersAndAvis < ActiveRecord::Migration[8.1]
  def change
    # Index composite pour accélérer les requêtes de filtrage par user + statut
    # (utilisé notamment dans ConversationPolicy::Scope et la sidebar du chat)
    # if_not_exists : l'index a déjà pu être créé en prod (déploiement partiel ou
    # ajout manuel) → migration idempotente pour ne pas planter sur PG::DuplicateTable.
    add_index :match_users, [:user_id, :status],
              name: "index_match_users_on_user_id_status", if_not_exists: true

    # Index composite pour accélérer les requêtes d'avis par utilisateur évalué + mutual
    # (utilisé sur la page profil pour afficher les avis mutuels en priorité)
    add_index :avis, [:reviewed_user_id, :mutual],
              name: "index_avis_on_reviewed_user_id_mutual", if_not_exists: true
  end
end
