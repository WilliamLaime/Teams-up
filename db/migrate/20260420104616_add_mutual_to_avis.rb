class AddMutualToAvis < ActiveRecord::Migration[8.1]
  def up
    # Ajoute la colonne mutual avec valeur par défaut false
    add_column :avis, :mutual, :boolean, default: false, null: false

    # Backfill — marque les avis mutuels existants
    # Un avis est mutuel si son inverse existe (même match, reviewer/reviewed inversés)
    execute <<-SQL
      UPDATE avis SET mutual = true
      WHERE EXISTS (
        SELECT 1 FROM avis a2
        WHERE a2.reviewer_id      = avis.reviewed_user_id
          AND a2.reviewed_user_id = avis.reviewer_id
          AND a2.match_id         = avis.match_id
      )
    SQL

    # Crée un index sur la colonne mutual pour les requêtes filtrées
    add_index :avis, :mutual, name: 'index_avis_on_mutual'
  end

  def down
    remove_index :avis, name: 'index_avis_on_mutual'
    remove_column :avis, :mutual
  end
end
