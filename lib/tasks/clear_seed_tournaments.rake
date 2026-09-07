# =============================================================================
# Nettoyage des tournois de démonstration (seeds)
#
# Utilité : la prod a hérité des tournois créés par `rake seed_tournament:*`.
# On ne garde que le ou les tournois réels, désignés par leur slug.
#
# Usage (dry-run par défaut, aucune écriture) :
#   rails tournaments:clear_seeds KEEP=open-d-automne-hiver-cacd2-lcl-lezqad
#
# Suppression effective :
#   rails tournaments:clear_seeds KEEP=open-d-automne-hiver-cacd2-lcl-lezqad CONFIRM=1
#
# Plusieurs slugs à conserver : les séparer par des virgules.
# La suppression passe par `destroy` (et non `delete_all`) pour déclencher les
# cascades du modèle : tours, matchs de tournoi, inscrits, et `nullify` des
# rencontres standard rattachées (qui sont donc préservées).
# =============================================================================
namespace :tournaments do
  desc "Supprime tous les tournois sauf ceux dont le slug est passé dans KEEP (dry-run sans CONFIRM=1)"
  task clear_seeds: :environment do
    keep = ENV["KEEP"].to_s.split(",").map(&:strip).reject(&:empty?)
    abort "KEEP est obligatoire — ex: KEEP=mon-tournoi-abc123" if keep.empty?

    kept = Tournament.where(slug: keep)
    missing = keep - kept.pluck(:slug)
    abort "Slug(s) introuvable(s) : #{missing.join(', ')} — rien n'a été supprimé." if missing.any?

    doomed = Tournament.where.not(slug: keep).order(:created_at)

    puts "Conservés (#{kept.count}) :"
    kept.each { |t| puts "  ✓ #{t.slug} — #{t.name}" }

    puts "\nÀ supprimer (#{doomed.count}) :"
    doomed.each do |t|
      puts format(
        "  ✗ #{t.slug} — #{t.name} (état: %s, inscrits: %d, tours: %d, rencontres liées: %d)",
        t.status, t.tournament_users.count, t.tournament_rounds.count, t.matches.count
      )
    end

    if ENV["CONFIRM"] != "1"
      puts "\nDRY-RUN : rien n'a été supprimé. Relancer avec CONFIRM=1 pour appliquer."
      next
    end

    destroyed = 0
    doomed.each do |tournament|
      Tournament.transaction { tournament.destroy! }
      destroyed += 1
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
      warn "  ! échec sur #{tournament.slug} : #{e.class} — #{e.message}"
    end

    puts "\n#{destroyed} tournoi(s) supprimé(s). Restants : #{Tournament.count}."
  end
end
