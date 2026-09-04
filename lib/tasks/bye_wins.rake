# Backfill one-shot du bilan V/D faussé par les byes de poule.
#
# Pourquoi cette tâche existe : jusqu'à la correction de
# RoundRobinStats#recompute_stats_for, un bye (joueur au repos, effectif impair)
# était compté comme un match GAGNÉ dans tournament_users.wins — il est clôturé
# avec `winner_id = player_a` pour que la journée puisse se terminer (cf.
# TournamentMatch#resolve_bye). Chaque joueur d'une poule de 3 portait donc une
# victoire fantôme. Deux conséquences en base :
#
#   1. les colonnes wins/losses affichées au classement sont fausses ;
#   2. la phase finale a été SEEDÉE sur ces colonnes (via Tournament#rank_key),
#      donc les têtes de série elles-mêmes sont fausses — les poules impaires ont
#      été avantagées d'une victoire par joueur.
#
# Le code corrigé ne réécrit ces colonnes qu'au prochain score saisi : les tournois
# déjà en cours resteraient faux jusque-là, et un tournoi dont les poules sont
# terminées ne les réécrirait plus JAMAIS. D'où ce rattrapage explicite.
#
# Rejouable sans risque : tout est recalculé depuis les matchs, jamais incrémenté.
#
# Utilisation — DRY-RUN PAR DÉFAUT, contrairement à match_formats:realign : cette
# tâche peut DÉTRUIRE des tours de phase finale devenus faux, il faut donc voir ce
# qu'elle ferait avant de la laisser écrire.
#
#   bin/rails tournaments:backfill_byes                  # simule (rollback)
#   bin/rails tournaments:backfill_byes APPLY=1          # écrit
#   bin/rails tournaments:backfill_byes SLUG=mon-tournoi # cible un seul tournoi
#
# En production, `railway ssh` et PAS `railway run` : `run` exécute la commande sur
# la machine locale, où l'hôte *.railway.internal de DATABASE_URL ne résout pas.
#
#   railway ssh --service Teams-up bin/rails tournaments:backfill_byes
namespace :tournaments do
  desc "Recalcule le bilan V/D des poules sans compter les byes, et reprend la phase finale seedée dessus"
  task backfill_byes: :environment do
    apply = ENV["APPLY"].present?
    scope = Tournament.where(format: Tournament::POOL_BASED_FORMATS).where.not(status: "completed")
    scope = scope.where(slug: ENV["SLUG"]) if ENV["SLUG"].present?

    puts apply ? "== ÉCRITURE ==" : "== SIMULATION (rien ne sera écrit) =="

    touched = 0

    scope.find_each do |tournament|
      # Photo AVANT, pour ne journaliser que les joueurs réellement corrigés.
      before = tournament.tournament_users.players.approved
                         .pluck(:id, :wins, :losses).to_h { |id, w, l| [id, [w, l]] }

      ActiveRecord::Base.transaction do
        TournamentEngine.for(tournament)
                        .recompute_stats_for("pool", apply_state: false, count_byes: false)

        drifted = tournament.tournament_users.players.approved.reload.reject do |tu|
          before[tu.id] == [tu.wins, tu.losses]
        end

        if drifted.any?
          touched += 1
          puts "\n#{tournament.slug} (#{tournament.format}, #{tournament.status})"
          drifted.each do |tu|
            was = before[tu.id]
            puts "  #{tu.display_name} : #{was[0]}V-#{was[1]}D -> #{tu.wins}V-#{tu.losses}D"
          end
          Tasks::ByeWins.rebuild_final_phase!(tournament)
        end

        raise ActiveRecord::Rollback unless apply
      end
    end

    puts "\n#{touched} tournoi(s) concerné(s)."
    puts "Relancer avec APPLY=1 pour écrire." unless apply
  end
end

# Namespacé plutôt que défini au top-level : une méthode déclarée à la racine d'un
# .rake atterrit sur Object et devient appelable depuis TOUTE l'application.
module Tasks
  module ByeWins
    # La phase finale a été construite sur les colonnes fausses : ses têtes de série
    # ne correspondent plus à ce que le classement corrigé produit. On la reprend.
    def self.rebuild_final_phase!(tournament)
      finals = tournament.tournament_rounds.final_phase
      return puts("  (aucune phase finale à reprendre)") if finals.none?

      if tournament.criterium?
        # #reconcile! ne détruit que l'aval RÉELLEMENT périmé — le premier tour dont
        # les joueurs ne sont plus ceux que la structure produirait aujourd'hui. Une
        # branche que le reseeding ne déplace pas garde ses scores.
        was = finals.count
        CriteriumFlow.new(tournament).reconcile!
        now = tournament.tournament_rounds.final_phase.count
        puts "  phase finale reprise : #{was} tour(s) avant, #{now} après"
      else
        # #next_round! est le point d'entrée public : les poules étant terminées, il
        # rebascule de lui-même en phase finale (PoolBuilder#start_playoffs!).
        tournament.bracket_rounds.destroy_all
        TournamentEngine.for(tournament).next_round!
        puts "  tableau final reconstruit (#{tournament.bracket_rounds.count} tour)"
      end
    end
  end
end
