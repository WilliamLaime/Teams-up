# ── Service TournamentStandings ───────────────────────────────────────────────
# Le classement final d'un Critérium Fédéral : qui finit à quelle place.
#
# ── Dérivé, jamais stocké ─────────────────────────────────────────────────────
# Aucune colonne `final_place`. Une place stockée devrait être réécrite après
# chaque score, chaque correction (#correct) et chaque forfait ; un seul chemin
# oublié et le classement mentirait sans que rien ne le signale. Ici, la place est
# recalculée à la lecture depuis les matchs, donc elle ne peut pas se désynchroniser.
#
# ── La règle de lecture, unique ────────────────────────────────────────────────
# La FINALE d'un tableau attribue `places.first` à son vainqueur et
# `places.first + 1` à son perdant. C'est vrai de la finale du tournoi (1er / 2e)
# comme du match pour la 23e place (23e / 24e) : CriteriumStructure a déjà rangé
# chaque tableau derrière la plage de places qu'il couvre, il n'y a donc qu'une
# seule règle à appliquer, récursivement — et comme CHAQUE place se joue, il n'y
# a aucun ex æquo à traiter : la structure ne produit que des tableaux.
#
# ── Pourquoi la compaction est obligatoire ────────────────────────────────────
# Les byes créent des places jamais attribuées : un tableau de 8 à 6 entrants
# n'envoie que 2 perdants vers son mini-tableau 5e-8e, donc les places 7 et 8 ne
# sont jouées par personne. Sans renumérotation, le classement afficherait un trou
# entre le 6e et le 9e. On renumérote donc 1..n en préservant les rangs partagés —
# seule #tail_groups peut encore en produire (joueurs qu'aucun tableau ne classe).
class TournamentStandings
  # Un rang du classement : une place, et les joueurs qui la partagent.
  Tier = Struct.new(:place, :players, :label) do
    def tied? = players.size > 1
  end

  def initialize(tournament)
    @tournament = tournament
  end

  # Le classement complet, du 1er au dernier, places compactées.
  def tiers = @tiers ||= compact(ordered_groups)

  # Les rangs RÉELLEMENT décidés par un match joué, à l'exclusion du repli par
  # position de poule (cf. #tail_groups).
  #
  # C'est ce que l'onglet Classement doit afficher : tant qu'aucun tableau n'a
  # livré de place, `tiers` ne contient que la queue, c'est-à-dire le classement
  # des poules recopié — un doublon exact des tables de poules affichées juste en
  # dessous, et un « Classement final » qui annonce des places que personne n'a
  # gagnées.
  #
  # `first(n)` suffit : #ordered_groups place toujours les groupes issus des
  # tableaux AVANT la queue, et la compaction préserve cet ordre.
  def decided_tiers = tiers.first(placed_groups.size)

  # La place d'un joueur, ou nil s'il n'en a pas encore (tournoi en cours).
  def place_of(tournament_user) = places_by_player[tournament_user.id]

  # Le vainqueur du tournoi : le 1er du classement. Passe par les places plutôt
  # que par « le vainqueur de la finale » pour rester juste si le tournoi a été
  # terminé à la main avant la fin du tableau (cf. TournamentsController#finish).
  def champion = tiers.first&.players&.first

  private

  def structure = @tournament.criterium_structure

  def places_by_player
    @places_by_player ||= tiers.each_with_object({}) do |tier, index|
      tier.players.each { |player| index[player.id] = tier.place }
    end
  end

  # ── Les groupes, dans l'ordre du classement ─────────────────────────────────
  def ordered_groups
    placed = placed_groups.sort_by(&:first).map(&:last)
    placed + tail_groups(placed.flatten)
  end

  # [[place brute, [joueurs]], …] tels que les tableaux les désignent. Les places
  # brutes peuvent comporter des trous (byes) : la compaction s'en charge.
  def placed_groups
    @placed_groups ||= structure.nodes.flat_map do |node|
      # Les barrages sont un nœud de transit : ils n'attribuent aucune place.
      node.elimination? ? final_groups(node) : []
    end
  end

  # La finale d'un tableau : vainqueur et perdant. Rien tant qu'elle n'est pas
  # jouée — un dernier tour à plusieurs matchs n'est pas une finale.
  def final_groups(node)
    final = rounds_of(node).last
    return [] if final.blank? || !final.complete?

    matches = final.tournament_matches.to_a
    return [] unless matches.size == 1

    match = matches.first
    return [] if match.winner.blank?

    groups = [[node.first_place, [match.winner]]]
    # Un bye en finale (tableau à 1 entrant réel) ne désigne pas de perdant.
    groups << [node.first_place + 1, [match.loser]] if match.loser.present?
    groups
  end

  def rounds_of(node)
    @tournament.tournament_rounds.where(phase: node.phase, branch: node.branch).ordered.to_a
  end

  # Les joueurs qu'aucun tableau ne classe : 5es de poule quand les poules
  # dépassent 4, poule unique sans phase finale, joueurs déclarés forfait (ils
  # n'entrent plus dans les tableaux ouverts après leur départ, cf.
  # CriteriumFlow#resolve). Groupés par position de poule, après la dernière place
  # attribuée — cas que le règlement ne couvre pas, on reste donc factuel et stable.
  #
  # ⚠️ Les partants passent DERNIERS, avant tout regroupement par poule : sans
  # cette partition, un partant 1er de poule se retrouverait classé devant un
  # joueur qui a joué tout le tournoi et fini 3e de la sienne.
  def tail_groups(already_placed)
    placed_ids = already_placed.to_set(&:id)
    rest = @tournament.approved_players.reject { |player| placed_ids.include?(player.id) }
    return [] if rest.empty?

    playing, quitters = rest.partition { |player| !player.withdrawn? }

    by_pool_position(playing) + by_pool_position(quitters)
  end

  def by_pool_position(players)
    players.group_by { |player| @tournament.pool_position_of(player) || Float::INFINITY }
           .sort_by(&:first)
           .map { |_position, group| by_strength(group) }
  end

  # Clé locale, et surtout PAS un préfixe posé sur Tournament#rank_key : ce dernier
  # sert le classement affiché de la ronde suisse et du championnat, ainsi que le
  # seeding des tableaux — y reléguer les partants sortirait du périmètre.
  def by_strength(players)
    players.sort_by { |player| [player.withdrawn? ? 1 : 0, *@tournament.rank_key(player)] }
  end

  # ── Compaction ──────────────────────────────────────────────────────────────
  # Renumérote 1..n en préservant les rangs partagés : un groupe de k joueurs
  # occupe k places, donc le groupe suivant commence k places plus loin.
  def compact(groups)
    counter = 0

    groups.map do |players|
      place = counter + 1
      counter += players.size

      Tier.new(place: place, players: players, label: label_for(place, players.size))
    end
  end

  def label_for(place, count)
    ordinal = place == 1 ? "1er" : "#{place}e"
    count > 1 ? "#{ordinal}s ex æquo" : ordinal
  end
end
