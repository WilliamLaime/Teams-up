# Backfill one-shot du score des forfaits.
#
# Pourquoi cette tâche existe : jusqu'à TournamentMatch#complete_forfeit_sets, un
# forfait était enregistré SANS aucune manche (0-0). Les quotients de départage
# (manches, puis points) l'ignoraient donc complètement, alors que le règlement
# le compte 11-0 à chaque manche. Le code corrigé ne complète un forfait qu'à sa
# prochaine sauvegarde : les forfaits déjà en base resteraient faux.
#
# Rejouable sans risque : un forfait déjà complet n'est plus touché, et les bilans
# sont recalculés depuis les matchs, jamais incrémentés.
#
# DRY-RUN PAR DÉFAUT : compléter un forfait peut changer un classement de poule,
# donc des barrages déjà tirés. Voir ce qui changerait avant d'écrire.
#
#   bin/rails tournaments:backfill_forfeit_scores                  # simule (rollback)
#   bin/rails tournaments:backfill_forfeit_scores APPLY=1          # écrit
#   bin/rails tournaments:backfill_forfeit_scores SLUG=mon-tournoi # un seul tournoi
#
# En production, `railway ssh` et PAS `railway run` (cf. bye_wins.rake) :
#
#   railway ssh --service Teams-up bin/rails tournaments:backfill_forfeit_scores
namespace :tournaments do
  desc "Complète le score des forfaits (11-0 par manche) et reprend les classements qui en dépendent"
  task backfill_forfeit_scores: :environment do
    apply = ENV["APPLY"].present?
    scope = Tournament.where.not(status: "completed")
    scope = scope.where(slug: ENV["SLUG"]) if ENV["SLUG"].present?

    puts apply ? "== ÉCRITURE ==" : "== SIMULATION (rien ne sera écrit) =="
    touched = 0

    scope.find_each do |tournament|
      forfeits = TournamentMatch.joins(:tournament_round)
                                .where(tournament_rounds: { tournament_id: tournament.id })
                                .where(forfeit: true, is_bye: false)
                                .where.not(retired_player_id: nil)
                                .to_a
      next if forfeits.empty?

      ActiveRecord::Base.transaction do
        changed = forfeits.reject do |match|
          before = match.sets
          match.save! # before_validation :complete_forfeit_sets
          match.sets == before
        end

        if changed.any?
          touched += 1
          puts "\n#{tournament.slug} (#{tournament.format}, #{tournament.status})"
          changed.each do |match|
            puts "  #{match.player_a.display_name} – #{match.player_b.display_name} : #{match.sets.inspect}"
          end

          %w[pool league].each do |phase|
            next unless tournament.tournament_rounds.exists?(phase: phase)

            TournamentEngine.for(tournament).recompute_stats_for(phase, apply_state: false, count_byes: false)
          end
          # Un classement de poule a pu bouger : #reconcile! ne reprend que l'aval
          # RÉELLEMENT périmé (cf. Tasks::ByeWins).
          Tasks::ByeWins.rebuild_final_phase!(tournament) if tournament.criterium?
        end

        raise ActiveRecord::Rollback unless apply
      end
    end

    puts "\n#{touched} tournoi(s) concerné(s)."
    puts "Relancer avec APPLY=1 pour écrire." unless apply
  end
end
