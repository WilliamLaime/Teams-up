# ── Service ForfeitMatch ──────────────────────────────────────────────────────
# Déclare le forfait d'un joueur sur UN match, avec le score au moment de l'arrêt
# (vide = forfait avant le match). La portée dépend de la phase (règle du
# Critérium, confirmée par l'organisateur) :
#
#   • match de POULE / de CHAMPIONNAT → forfait pour CE match seulement. Le joueur
#     dispute tous ses matchs suivants — une poule ne bloque jamais la suite, même
#     après plusieurs forfaits. Il reste classé (0 point-partie par forfait, cf.
#     PoolStandings) et garde son accès au barrage, au tableau final ou à la
#     consolante selon son rang. Son `state` n'est donc PAS touché : c'est ce qui
#     laisse les journées suivantes se générer normalement (RoundRobinStats
#     #build_match! ne pose un forfait d'office que pour un joueur `withdrawn`).
#
#   • toute autre phase (barrage, tableau final, consolante, matchs de classement,
#     ronde suisse) → forfait pour le RESTE du tournoi, matchs de classement
#     compris : délégué à WithdrawPlayer, qui passe le joueur en `withdrawn`.
#
# Le score est complété par le modèle (TournamentMatch#complete_forfeit_sets) :
# 11-0 par manche avant le match, manche entamée terminée pendant le match.
class ForfeitMatch
  # Phases où un forfait ne vaut que pour le match.
  MATCH_ONLY_PHASES = %w[pool league].freeze

  def initialize(tournament, match, retired_player, sets: [])
    @tournament     = tournament
    @match          = match
    @retired_player = retired_player
    @sets           = sets
  end

  # Le forfait vaut-il pour ce match seulement ? (lu aussi par la vue, pour
  # annoncer la conséquence AVANT que l'organisateur ne valide.)
  def self.match_only?(match) = MATCH_ONLY_PHASES.include?(match.tournament_round.phase)

  # Renvoie le match si le forfait est enregistré, nil sinon (erreurs sur le match).
  def call!
    saved = ActiveRecord::Base.transaction do
      @match.assign_score(@sets)
      @match.forfeit = true
      @match.retired_player = @retired_player
      raise ActiveRecord::Rollback unless @match.save

      true
    end
    return nil unless saved

    self.class.match_only?(@match) ? advance_round_robin! : WithdrawPlayer.new(@tournament, @retired_player).call!
    @match
  end

  private

  # Même enchaînement qu'une saisie de score (cf. TournamentMatchesController
  # #update) : bilans de la phase recalculés, journée suivante générée si celle-ci
  # est complète.
  def advance_round_robin!
    round = @match.tournament_round.reload
    engine = TournamentEngine.for(@tournament)
    engine.recompute_stats_for(round.phase, apply_state: false, count_byes: false)
    engine.next_round! if round.complete?
  end
end
