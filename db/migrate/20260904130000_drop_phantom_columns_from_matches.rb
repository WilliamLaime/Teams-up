# Supprime trois colonnes « fantômes » de la table `matches`.
#
# ── Contexte ────────────────────────────────────────────────────────────────
# `max_supporters`, `pin_latitude` et `pin_longitude` figuraient dans
# `db/schema.rb` alors qu'aucune migration ne les crée et qu'aucune ligne de code
# ne les lit ni ne les écrit — vérifié sur l'intégralité de l'historique Git.
#
# Elles proviennent de la base locale d'un poste de développement, re-déversée
# dans `schema.rb` à chaque `db:migrate`. Le fichier oscillait donc depuis des
# mois (25 commits d'aller-retour) : les dumps de ce poste rajoutaient les trois
# lignes, ceux des autres postes les retiraient.
#
# ── Pourquoi une migration et pas juste une correction de schema.rb ─────────
# Corriger `schema.rb` seul serait une rustine : le prochain `db:migrate` du
# poste concerné les remettrait. Il faut supprimer les colonnes *dans les bases*
# qui les possèdent, sinon l'écart se reproduit indéfiniment.
#
# ── Pourquoi `if column_exists?` ────────────────────────────────────────────
# L'état diffère d'une base à l'autre : les postes à jour via `db:migrate` ne les
# ont pas, celui à l'origine du dump les a. La migration doit donc passer sans
# erreur dans les deux cas — no-op ici, suppression là-bas. C'est cette
# idempotence qui met fin à l'oscillation pour tout le monde.
class DropPhantomColumnsFromMatches < ActiveRecord::Migration[8.1]
  PHANTOM_COLUMNS = %i[max_supporters pin_latitude pin_longitude].freeze

  def up
    PHANTOM_COLUMNS.each do |column|
      remove_column :matches, column if column_exists?(:matches, column)
    end
  end

  # Volontairement irréversible : ces colonnes n'ont jamais eu de définition
  # d'origine dans une migration, il n'y a donc pas d'état antérieur fiable à
  # restaurer. Les recréer ne ferait que ressusciter le bug que l'on corrige.
  def down
    raise ActiveRecord::IrreversibleMigration,
          "Colonnes fantômes jamais utilisées : leur suppression n'a pas d'inverse utile."
  end
end
