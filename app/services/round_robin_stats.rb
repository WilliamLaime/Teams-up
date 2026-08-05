# ── Module RoundRobinStats ────────────────────────────────────────────────────
# Recalcul du bilan V/N/D + sets/points d'un joueur depuis les matchs d'une phase.
# Partagé par les trois moteurs (SwissPairing, LeagueBuilder, PoolBuilder) : la
# seule différence est la PHASE lue et l'application (ou non) de l'état suisse
# (qualified à 3 V / eliminated à 3 D) — d'où le paramètre `apply_state`. Les nuls
# (Lot 6) ne concernent que les sports collectifs à barème V/N/D (foot, hand).
#
# Le module attend une variable d'instance `@tournament` chez l'hôte, et — quand
# `apply_state: true` — une méthode `state_for(wins, losses)` (spécifique au suisse).
module RoundRobinStats
  # Recalcule wins/draws/losses + sets_won/lost + points_won/lost de chaque joueur
  # approuvé, à partir de TOUS les matchs de la phase donnée.
  #   • apply_state: true  → met aussi à jour `state` via `state_for` (suisse).
  #   • apply_state: false → laisse `state` inchangé (championnat / poules, où la
  #     qualification est décidée par le classement final, pas par un seuil 3 V/3 D).
  def recompute_stats_for(phase, apply_state:)
    matches = matches_in_phase(phase).to_a
    player_scope.find_each do |tu|
      played = matches.select { |m| m.player_a_id == tu.id || m.player_b_id == tu.id }
      wins   = played.count { |m| m.winner_id == tu.id }
      draws  = played.count(&:draw?)
      losses = played.count { |m| m.winner_id.present? && m.winner_id != tu.id }

      attrs = {
        wins: wins, draws: draws, losses: losses,
        sets_won: played.sum { |m| m.sets_won_by(tu) },
        sets_lost: played.sum { |m| m.sets_won_by(m.opponent_of(tu)) },
        points_won: played.sum { |m| m.points_won_by(tu) },
        points_lost: played.sum { |m| m.points_lost_by(tu) }
      }
      # "withdrawn" est terminal : on ne le recalcule jamais (sinon un abandon
      # serait ré-écrasé en active/eliminated et le joueur reviendrait dans les tirages).
      attrs[:state] = state_for(wins, losses) if apply_state && !tu.withdrawn?
      tu.update!(attrs)
    end
  end

  # Crée un match d'une journée round-robin en gérant les cas particuliers :
  #   • bye        : un seul joueur présent (l'autre est nil, effectif impair) ;
  #   • forfait    : un joueur a déjà abandonné (state "withdrawn") → le match est
  #     posé en forfait, l'adversaire gagne d'office (cf. TournamentMatch).
  # Utilisé par LeagueBuilder / PoolBuilder pour que les journées générées APRÈS un
  # abandon n'attendent pas un score du joueur retiré.
  def build_match!(round, player_a, player_b, position)
    if player_a.nil? || player_b.nil?
      return round.tournament_matches.create!(player_a: player_a || player_b, is_bye: true, position: position)
    end

    retired = [player_a, player_b].find(&:withdrawn?)
    if retired
      return round.tournament_matches.create!(
        player_a: player_a, player_b: player_b, position: position,
        forfeit: true, retired_player: retired
      )
    end

    round.tournament_matches.create!(player_a: player_a, player_b: player_b, position: position)
  end

  private

  # Inscriptions joueurs approuvées (relation, requêtée à frais à chaque appel).
  def player_scope = @tournament.tournament_users.players.approved

  # ── Ordre STABLE des joueurs, base de tout calendrier round-robin ─────────────
  # LeagueBuilder et PoolBuilder recalculent leur calendrier à CHAQUE appel de
  # `next_round!` et ne persistent que la journée manquante. Ce design n'est
  # correct que si cet ordre est TOTAL : deux lectures doivent rendre exactement la
  # même séquence, sinon le calendrier se décale d'une journée à l'autre —
  # certaines rencontres sont programmées deux fois, d'autres jamais, et la phase
  # peut ne jamais se terminer.
  #
  # `draw_order` (le tirage au sort figé au lancement, cf.
  # TournamentsController#assign_draw_order!) ne suffit PAS : il est nullable et
  # n'a jamais été backfillé, donc tous les tournois lancés avant sa migration ont
  # un draw_order nul de bout en bout. `ORDER BY draw_order` laisse alors Postgres
  # libre de rendre les lignes dans n'importe quel ordre — et cet ordre change
  # réellement en cours de tournoi, parce que `recompute_stats_for` réécrit le
  # bilan de chaque joueur entre deux journées et déplace les tuples dans le heap.
  #
  # D'où `:id` en dernier critère : unique par construction, donc l'ordre est total
  # même sans tirage au sort, tout en laissant `draw_order` décider quand il existe.
  def ordered_player_scope = player_scope.order(:draw_order, :id)

  # Tous les matchs d'une phase de ce tournoi (requête fraîche).
  def matches_in_phase(phase)
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: @tournament.id, phase: phase })
  end
end
