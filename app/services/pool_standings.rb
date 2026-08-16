# ── Service PoolStandings ─────────────────────────────────────────────────────
# Classement d'UNE poule au règlement FFTT (Critérium Fédéral).
#
#   • Points-parties : 2 par victoire, 1 par défaite JOUÉE, 0 par forfait
#     (cf. Sport#pool_points_rules, qui porte le barème par sport).
#   • Départage des ex-æquo, RESTREINT au sous-groupe et récursif :
#       (a) points-parties de la confrontation directe entre les seuls ex-æquo
#       (b) QUOTIENT de manches (gagnées / perdues) sur ces mêmes matchs
#       (c) QUOTIENT de points  (gagnés  / perdus)  sur ces mêmes matchs
#       (d) draw_order — le tirage au sort figé au lancement du tournoi
#
# Pourquoi un service et pas Tournament#rank_key : `rank_key` est une clé de tri
# PLATE, elle ne peut pas exprimer « restreint au sous-groupe d'ex-æquo ». Les deux
# coexistent — `rank_key` reste la source de vérité de la ronde suisse et du
# championnat, ce service ne sert qu'aux poules du Critérium.
#
# Deux différences assumées avec les colonnes de TournamentUser :
#   • QUOTIENTS et non différences (#set_average / #point_average sont des
#     différences) : le règlement FFTT départage au quotient.
#   • les BYES ne comptent pas. Dans une poule de 3, le calendrier round-robin
#     donne un bye par joueur ; le compter comme une victoire (ce que fait
#     RoundRobinStats#recompute_stats_for) offrirait 2 points-parties gratuits à
#     tout le monde. Une poule de 3 se joue en 2 matchs par joueur, point.
#
# Déterminisme absolu : aucun `shuffle` / `rand`. `draw_order` est la seule source
# d'aléa, tirée une fois au lancement — c'est la condition pour qu'une correction de
# score (TournamentMatchesController#correct) reconstruise un classement identique.
class PoolStandings
  # Ligne de classement prête à afficher (cf. _ranking_table.html.erb).
  Row = Data.define(:player, :place, :points, :played, :wins, :losses,
                    :sets_won, :sets_lost, :points_won, :points_lost, :reason)

  # `members` : les inscriptions d'UNE poule. `matches` : les matchs de phase
  # "pool" du tournoi — injectable pour éviter N requêtes quand on classe les
  # 8 poules d'affilée (cf. Tournament#pool_standings).
  def initialize(tournament, members, matches: nil)
    @tournament = tournament
    @members    = members.to_a
    @member_ids = @members.to_set(&:id)
    # Byes exclus (cf. en-tête) et matchs indécis ignorés : un match non joué ne
    # rapporte rien et ne peut pas servir de critère de départage.
    @matches = (matches || fetch_pool_matches).reject(&:is_bye)
                                              .select { |m| internal?(m) && m.status == "completed" }
  end

  # Les joueurs de la poule, du 1er au dernier.
  def ordered
    @ordered ||= @members.group_by { |player| points_of(player) }
                         .sort_by { |points, _| -points }
                         .flat_map { |_points, group| ordered_group(group) }
  end

  # Le joueur classé `rank` (1-based), ou nil si la poule est plus petite.
  # C'est cette méthode qui décide qui part en tableau final, en barrage ou en
  # consolante (cf. CriteriumStructure).
  def qualifier(rank) = ordered[rank - 1]

  # Position (1-based) d'un joueur dans sa poule.
  def place_of(player) = ordered.index { |p| p.id == player.id }&.succ

  # Lignes de classement, dans l'ordre.
  def rows
    ordered.each_with_index.map do |player, index|
      played = played_by(player)
      Row.new(
        player: player, place: index + 1, points: points_of(player), played: played.size,
        wins: played.count { |m| m.winner_id == player.id },
        losses: played.count { |m| m.winner_id.present? && m.winner_id != player.id },
        sets_won: played.sum { |m| m.sets_won_by(player) },
        sets_lost: played.sum { |m| m.sets_won_by(m.opponent_of(player)) },
        points_won: played.sum { |m| m.points_won_by(player) },
        points_lost: played.sum { |m| m.points_lost_by(player) },
        reason: nil
      )
    end
  end

  # La poule est-elle intégralement jouée ? (garde avant de qualifier qui que ce soit)
  def complete?
    @members.combination(2).all? { |a, b| played_between?(a, b) }
  end

  private

  # ── Départage ───────────────────────────────────────────────────────────────
  # Ordonne un sous-groupe d'ex-æquo. Récursif : après application des critères,
  # le sous-groupe peut se scinder en sous-sous-groupes encore à égalité, qu'on
  # départage à leur tour sur LEURS matchs internes uniquement (pratique FFTT).
  def ordered_group(group)
    return group if group.size <= 1

    # Seuls les matchs entre membres du sous-groupe comptent — c'est tout l'objet
    # de la « poule restreinte » du règlement.
    sub = matches_between(group)
    # La confrontation directe n'est significative que si tous les ex-æquo se sont
    # rencontrés. Sinon (poule en cours, forfait) on saute le critère (a).
    direct = round_robin_complete?(group, sub)

    buckets = group.group_by { |player| tiebreak_key(player, sub, direct: direct) }
                   .sort_by(&:first)
    # Aucun critère ne sépare le groupe → (d) tirage au sort. C'est aussi ce qui
    # TERMINE la récursion : sans cette garde, un groupe inséparable bouclerait.
    return group.sort_by { |player| player.draw_order.to_i } if buckets.size == 1

    buckets.flat_map { |_key, tied| ordered_group(tied) }
  end

  # Clé de tri CROISSANTE (d'où les négations : plus haut = mieux classé).
  def tiebreak_key(player, sub, direct:)
    [
      direct ? -points_in(player, sub) : 0,
      -quotient(sum(sub, player) { |m| m.sets_won_by(player) },
                sum(sub, player) { |m| m.sets_won_by(m.opponent_of(player)) }),
      -quotient(sum(sub, player) { |m| m.points_won_by(player) },
                sum(sub, player) { |m| m.points_lost_by(player) })
    ]
  end

  # QUOTIENT, pas différence. Aucune manche/point concédé = avantage maximal ;
  # 0/0 (aucun match joué) = 0.0. Jamais de ZeroDivisionError.
  def quotient(won, lost)
    return won.zero? ? 0.0 : Float::INFINITY if lost.zero?

    won.fdiv(lost)
  end

  # ── Points-parties ──────────────────────────────────────────────────────────
  def points_of(player) = points_in(player, @matches)

  def points_in(player, matches)
    matches.sum { |match| match_points(match, player) }
  end

  def match_points(match, player)
    return 0 unless match.player_a_id == player.id || match.player_b_id == player.id
    return rules[:win]  if match.winner_id == player.id
    return rules[:draw] if match.draw?
    return 0 if match.winner_id.blank? # match sans vainqueur ni nul → rien

    # Défaite : 1 point si elle a été jouée, 0 si le joueur a déclaré forfait.
    match.retired_player_id == player.id ? rules[:forfeit] : rules[:loss]
  end

  def rules
    @rules ||= @tournament.sport&.pool_points_rules || { win: 1, draw: 0, loss: 0, forfeit: 0 }
  end

  # ── Accès aux matchs ────────────────────────────────────────────────────────
  def played_by(player)
    @matches.select { |m| m.player_a_id == player.id || m.player_b_id == player.id }
  end

  def matches_between(group)
    ids = group.to_set(&:id)
    @matches.select { |m| ids.include?(m.player_a_id) && ids.include?(m.player_b_id) }
  end

  def played_between?(player_a, player_b)
    @matches.any? do |m|
      [m.player_a_id, m.player_b_id].sort == [player_a.id, player_b.id].sort
    end
  end

  # Tous les membres du groupe se sont-ils rencontrés ?
  def round_robin_complete?(group, sub)
    ids = group.map(&:id)
    pairs = sub.to_set { |m| [m.player_a_id, m.player_b_id].sort }
    ids.combination(2).all? { |pair| pairs.include?(pair.sort) }
  end

  # Somme sur les matchs de `player` uniquement (évite de compter les matchs des
  # autres membres du sous-groupe).
  def sum(matches, player, &)
    matches.select { |m| m.player_a_id == player.id || m.player_b_id == player.id }.sum(&)
  end

  # Les deux joueurs du match appartiennent-ils à cette poule ?
  def internal?(match)
    @member_ids.include?(match.player_a_id) &&
      (match.player_b_id.nil? || @member_ids.include?(match.player_b_id))
  end

  def fetch_pool_matches
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: @tournament.id, phase: "pool" })
                   .to_a
  end
end
