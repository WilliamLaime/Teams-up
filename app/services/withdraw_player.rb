# ── Service WithdrawPlayer ────────────────────────────────────────────────────
# Déclare le forfait / l'abandon d'un joueur (Lot 5) :
#   1. passe son inscription en state "withdrawn" ;
#   2. transforme ses matchs NON décidés (présents, tous formats confondus) en
#      victoires par forfait pour l'adversaire (cf. TournamentMatch#derive_winner_from_sets) ;
#   3. relance le moteur (idempotent) : recalcule le classement et, si la ronde
#      courante est désormais complète, enchaîne la suite.
#
# Les matchs FUTURS sont gérés à la génération : le suisse ignore les joueurs non
# "active", et LeagueBuilder/PoolBuilder posent un forfait via build_match! quand
# un joueur withdrawn réapparaît dans une journée à venir.
class WithdrawPlayer
  def initialize(tournament, tournament_user)
    @tournament = tournament
    @tournament_user = tournament_user
  end

  def call!
    ActiveRecord::Base.transaction do
      @tournament_user.update!(state: "withdrawn")
      forfeit_pending_matches!
    end

    # Hors transaction : le moteur ouvre la sienne (recompute + génération éventuelle).
    TournamentEngine.for(@tournament).next_round!
  end

  private

  # Matchs en cours du joueur (non décidés, hors byes) → forfait.
  def forfeit_pending_matches!
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: @tournament.id })
                   .where(is_bye: false, winner_id: nil)
                   .where("player_a_id = :id OR player_b_id = :id", id: @tournament_user.id)
                   .find_each do |match|
      match.update!(forfeit: true, retired_player_id: @tournament_user.id)
    end
  end
end
