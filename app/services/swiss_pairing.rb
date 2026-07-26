# ── Service SwissPairing ──────────────────────────────────────────────────────
# Moteur de la Ronde Suisse (Lot 3). Deux responsabilités séparées :
#
#   • #build_pairs  : l'ALGORITHME PUR d'appariement (aucun accès base). Il prend
#     une liste de joueurs (répondant à #id et #wins) + l'historique des paires
#     déjà jouées, et renvoie les appariements de la ronde suivante. Testable seul.
#
#   • #next_round!  : la PERSISTANCE. Recalcule le bilan V/D, applique les
#     qualifications (3 V) / éliminations (3 D), décide s'il faut continuer la
#     ronde suisse ou basculer sur le tableau final, puis crée la ronde et ses matchs.
#
# Principe de la ronde suisse : tirage intégral à chaque ronde, on n'apparie JAMAIS
# deux fois les mêmes adversaires. On regroupe les joueurs par nombre de victoires
# (« score groups »), on apparie dans le groupe, et on fait « flotter » un joueur
# vers le groupe suivant si l'effectif est impair. Le moteur ne lève JAMAIS
# d'exception : en dernier recours il autorise un match déjà joué (cf. #force_pair).
#
# Exemple :
#   SwissPairing.new(tournament).next_round!
class SwissPairing
  # Recalcul du bilan V/D + sets/points (partagé avec les moteurs championnat/poules).
  include RoundRobinStats

  # tournament peut être nil quand on ne se sert que de l'algorithme pur (#build_pairs).
  def initialize(tournament = nil)
    @tournament = tournament
  end

  # ── Algorithme pur ────────────────────────────────────────────────────────────
  # @param players [Array] joueurs actifs (répondent à #id, #wins, #set_average, #point_average)
  # @param played_pairs [Set] paires déjà jouées, chacune = [id_min, id_max]
  # @param byed_ids [Set] ids des joueurs ayant déjà été exemptés (bye)
  # @return [Hash] { pairs: [[a, b], …], bye: joueur_ou_nil }
  def build_pairs(players, played_pairs: Set.new, byed_ids: Set.new)
    players = players.dup
    bye = nil

    # 1. Effectif impair → un joueur est exempté (bye = victoire automatique).
    #    On choisit le joueur le moins bien classé n'ayant pas encore eu de bye.
    if players.size.odd?
      bye = pick_bye(players, byed_ids)
      players -= [bye]
    end

    # 2. Trier par nombre de victoires décroissant : le backtracking essaiera
    #    d'apparier chaque joueur avec le suivant le mieux classé → il reste au
    #    plus près des « score groups » et ne fait flotter que si nécessaire.
    ordered = players.sort_by { |p| [-p.wins, -p.set_average, -p.point_average, p.id] }

    # 3. Recherche globale d'un appariement SANS rematch (backtracking borné).
    #    Si aucune solution n'existe, on relâche la contrainte (force_pair).
    @steps = 0
    pairs = match_within(ordered, played_pairs) || force_pair(ordered, played_pairs)

    { pairs: pairs, bye: bye }
  end

  # ── Persistance ─────────────────────────────────────────────────────────────
  # Génère la ronde suivante (ou la première). Idempotent : renvoie la ronde
  # courante sans rien créer tant qu'elle n'est pas terminée. Bascule
  # automatiquement sur le tableau final quand la phase suisse est finie.
  def next_round!
    ActiveRecord::Base.transaction do
      current = @tournament.current_round
      # Ronde en cours non terminée → on ne génère rien (protège des double-clics).
      return current if current && !current.complete?

      # Clôturer la ronde qui vient de se terminer.
      current&.update!(status: "completed")

      # Le tableau final a déjà commencé → on le fait avancer (tour suivant / fin).
      return BracketBuilder.new(@tournament).advance! if @tournament.bracket_started?

      # Recalcul déterministe du bilan V/D + qualifications/éliminations.
      recompute_stats_for("swiss", apply_state: true)

      if ready_for_bracket?
        BracketBuilder.new(@tournament).build!
      else
        create_swiss_round!
      end
    end
  end

  private

  # ── Algorithme pur : helpers ──────────────────────────────────────────────────

  # Joueur exempté : le moins de victoires, en priorité parmi ceux jamais exemptés.
  def pick_bye(players, byed_ids)
    never_byed = players.reject { |p| byed_ids.include?(p.id) }
    pool = never_byed.presence || players
    pool.min_by(&:wins)
  end

  # Budget d'exploration du backtracking : au-delà, on abandonne la recherche
  # exacte (retourne nil → force_pair). Protège des explosions combinatoires sur
  # les effectifs bâtards sans jamais planter.
  MAX_STEPS = 200_000

  # Appariement exact par backtracking, en évitant les rematchs. La liste est
  # triée par force : essayer les partenaires dans l'ordre garde les joueurs de
  # même niveau ensemble et ne fait flotter que lorsque c'est nécessaire.
  # nil si aucune solution sans rematch (ou budget dépassé).
  def match_within(pool, played_pairs)
    return [] if pool.empty?

    @steps += 1
    return nil if @steps > MAX_STEPS

    first, *rest = pool
    rest.each_with_index do |partner, idx|
      next if rematch?(first, partner, played_pairs)

      remaining = rest[0...idx] + rest[(idx + 1)..]
      sub = match_within(remaining, played_pairs)
      return [[first, partner]] + sub if sub
    end
    nil
  end

  # Dernier recours anti-plantage : apparie coûte que coûte (rematch toléré),
  # en privilégiant tout de même un adversaire encore jamais rencontré.
  def force_pair(pool, played_pairs)
    pool = pool.dup
    pairs = []
    while pool.size >= 2
      player = pool.shift
      idx = pool.index { |other| !rematch?(player, other, played_pairs) } || 0
      pairs << [player, pool.delete_at(idx)]
    end
    pairs
  end

  def rematch?(one, two, played_pairs)
    played_pairs.include?([one.id, two.id].minmax)
  end

  # ── Persistance : helpers ─────────────────────────────────────────────────────

  # État suisse dérivé du bilan V/D (appelé par RoundRobinStats via apply_state).
  def state_for(wins, losses) = TournamentUser.state_for(wins, losses)

  # Faut-il arrêter la ronde suisse et lancer le tableau final ?
  def ready_for_bracket?
    return true if player_scope.qualified.count >= @tournament.final_size
    return true if player_scope.active.count < 2 # plus assez de monde pour apparier
    # Tout le monde restant tiendra dans le tableau → inutile de continuer.
    return true if player_scope.qualified.count + player_scope.active.count <= @tournament.final_size

    false
  end

  # Crée la ronde suisse suivante et ses matchs.
  def create_swiss_round!
    result = build_pairs(player_scope.active.to_a, played_pairs: played_pairs_set, byed_ids: byed_ids_set)
    number = @tournament.tournament_rounds.swiss.count + 1
    round = @tournament.tournament_rounds.create!(phase: "swiss", number: number, status: "in_progress")

    position = 0
    result[:pairs].each do |a, b|
      round.tournament_matches.create!(player_a: a, player_b: b, position: position)
      position += 1
    end
    round.tournament_matches.create!(player_a: result[:bye], is_bye: true, position: position) if result[:bye]

    round
  end

  # Tous les matchs de la phase suisse de ce tournoi (requête fraîche).
  def swiss_matches = matches_in_phase("swiss")

  # Ensemble des paires déjà jouées (byes exclus).
  def played_pairs_set
    swiss_matches.where.not(player_b_id: nil).pluck(:player_a_id, :player_b_id)
                 .to_set(&:minmax)
  end

  # Ids des joueurs ayant déjà été exemptés.
  def byed_ids_set
    swiss_matches.where(is_bye: true).pluck(:player_a_id).to_set
  end
end
