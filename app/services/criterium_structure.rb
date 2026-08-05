# ── Service CriteriumStructure ────────────────────────────────────────────────
# DÉCLARE la topologie d'un Critérium Fédéral : quels tableaux existent, qui y
# entre, et quelles places chacun attribue. Rien d'autre.
#
# Pur Ruby : aucun ActiveRecord, aucune écriture, aucun aléa. C'est volontaire —
# c'est ici que vit la conformité au règlement FFTT, donc c'est ici qu'on la
# prouve par des tests, sans base de données ni tournoi. CriteriumFlow (Lot 4)
# se contentera de matérialiser en TournamentRound ce que ce service décrit.
#
# ── La formule qui porte tout ─────────────────────────────────────────────────
# Pour un tableau de `size` places dont la première place attribuée est `offset`,
# les perdants du tour `r` sont `size / 2**r` joueurs qui se disputent les places
# à partir de `offset + size / 2**r`.
#
#   Tableau OK de 16, offset 1 :  1/2 → 2 perdants → places 3-4
#                                 1/4 → 4 perdants → places 5-8
#                                 1/8 → 8 perdants → places 9-16
#   Consolante de 16, offset 17 : finale → 17/18 · 1/2 → 19/20 · 1/4 → 21-24…
#
# TOUS les chiffres du règlement tombent de cette seule récursion. La variante
# « classement intégral » n'en diffère que par un seuil : au-delà de TIE_FROM
# perdants sur un même tour on classe ex æquo, sinon on fait rejouer. En mode
# intégral ce seuil est infini → aucun ex æquo, chaque place est jouée.
class CriteriumStructure
  # ── Sources d'entrants ──────────────────────────────────────────────────────
  # D'où viennent les joueurs d'un tableau. Ce sont des DESCRIPTIONS : c'est
  # CriteriumFlow qui les résout en vrais TournamentUser.
  PoolQualifiers = Data.define(:rank)        # les Ne de chaque poule
  Winners        = Data.define(:key, :round) # vainqueurs du tour N d'un tableau
  Losers         = Data.define(:key, :round) # perdants du tour N d'un tableau

  # ── Un nœud = un tableau (ou un palier d'ex æquo) ───────────────────────────
  #   key      : identifiant unique et stable ("ok", "ko", "ok:5-8"…)
  #   phase    : la phase TournamentRound correspondante
  #   branch   : la branche TournamentRound (2e dimension de l'index unique)
  #   kind     : :elimination (tableau) · :playoff (tour unique) · :tie (ex æquo)
  #   sources  : qui entre ici
  #   pairing  : comment apparier le 1er tour (cf. CriteriumFlow)
  #   places   : [première, dernière] place couverte — nil = nœud de transit
  #   tie_at   : place commune attribuée aux ex æquo (nœuds :tie uniquement)
  #   size     : nombre de places du tableau (puissance de 2 pour :elimination)
  #   entrants : nombre de joueurs qui y entrent réellement (≤ size → byes)
  Node = Data.define(:key, :phase, :branch, :label, :kind, :sources, :pairing,
                     :places, :tie_at, :size, :entrants) do
    def elimination? = kind == :elimination
    def tie?         = kind == :tie
    # Nœud de TRANSIT : n'attribue aucune place, et ses DEUX camps continuent
    # (vainqueurs → tableau final, perdants → consolante). Seuls les barrages.
    def transit?     = kind == :playoff

    def first_place = places&.first
    def last_place  = places&.last

    # Nombre de tours à jouer : un palier d'ex æquo ne se joue pas, un barrage
    # est un tour unique, un tableau se joue en log2(size) tours.
    def round_count
      case kind
      when :tie     then 0
      when :playoff then 1
      else Integer(Math.log2(size))
      end
    end

    # Nombre de cartes de match générées par ce nœud, byes inclus (un tableau de
    # `size` places produit toujours `size - 1` cartes, quelle que soit la façon
    # dont ses perdants sont ensuite reclassés — ceux-là comptent pour leur
    # propre nœud).
    def match_count
      case kind
      when :tie     then 0
      when :playoff then entrants / 2
      else size - 1
      end
    end
  end

  # Au-delà de ce nombre de perdants sur un même tour, le règlement les classe
  # ex æquo plutôt que de les faire rejouer (8 joueurs → « 9es ex æquo »).
  TIE_FROM = 8

  # `pool_count`       : nombre de poules
  # `players_per_pool` : 3 ou 4 (le 4e de poule descend directement en consolante)
  # `mode`             : :standard (barrages + OK + consolante), :integral (tableau
  #                      unique, chaque place jouée — effectifs réduits) ou :none
  #                      (poule unique : le classement de la poule EST le classement
  #                      final, aucune phase finale — cf. Tournament#criterium_mode)
  # `player_count`     : effectif réel, utile en mode intégral quand les poules
  #                      sont inégales. Par défaut pool_count × players_per_pool.
  def initialize(pool_count:, players_per_pool: 4, mode: :standard, player_count: nil)
    @pool_count       = pool_count
    @players_per_pool = players_per_pool
    @mode             = mode
    @player_count     = player_count || (pool_count * players_per_pool)
  end

  # Tous les nœuds, dans l'ordre de déroulement (barrages, puis tableau final et
  # ses classements, puis consolante et les siens). Memoïsé : la structure est
  # une fonction pure de ses paramètres.
  def nodes
    @nodes ||= case @mode
               when :none     then []
               when :integral then integral_nodes
               else                standard_nodes
               end
  end

  def node(key) = nodes.find { |n| n.key == key }

  # Les nœuds dont les entrants viennent des poules ou des barrages, c'est-à-dire
  # ceux qu'il faut créer d'emblée (les autres naissent de leurs perdants).
  def root_nodes = nodes.select { |n| n.transit? || %w[ok ko].include?(n.key) }

  # Effectif total entrant en phase finale. Doit égaler l'effectif du tournoi :
  # poules de 4 → OK 2n + consolante 2n = 4n · poules de 3 → OK 2n + KO n = 3n.
  # C'est l'invariant « aucun joueur perdu, aucun en double ».
  def final_phase_entrants
    nodes.reject(&:transit?).select { |n| %w[ok ko].include?(n.key) }.sum(&:entrants)
  end

  private

  def integral? = @mode == :integral

  # Seuil d'ex æquo : désactivé en mode intégral (chaque place est jouée).
  def tie_from = integral? ? Float::INFINITY : TIE_FROM

  # ── Mode standard : barrages + tableau final + consolante ───────────────────
  def standard_nodes
    [barrage_node] + ok_nodes + ko_nodes
  end

  # Barrages : les 2es contre les 3es de poule, croisés. Nœud de transit — les
  # vainqueurs montent au tableau final, les perdants descendent en consolante.
  def barrage_node
    entrants = @pool_count * 2

    Node.new(key: "barrage", **coords("barrage"), label: "Barrages", kind: :playoff,
             sources: [PoolQualifiers[2], PoolQualifiers[3]], pairing: :cross_pool,
             places: nil, tie_at: nil, size: entrants, entrants: entrants)
  end

  # Tableau final : les 1ers de poule (exemptés de barrage) + les vainqueurs de
  # barrage. Places 1 à ok_size.
  def ok_nodes
    placement_tree(prefix: "ok", key: "ok", label: "Tableau final",
                   sources: [PoolQualifiers[1], Winners["barrage", 1]],
                   pairing: :exempt_first,
                   size: ok_size, offset: 1, entrants: @pool_count * 2)
  end

  # Consolante : les perdants de barrage, plus les 4es de poule quand les poules
  # sont à 4 (en poules de 3 il n'y a pas de 4e). Places ok_size + 1 et suivantes.
  def ko_nodes
    sources = if @players_per_pool >= 4
                [PoolQualifiers[4], Losers["barrage", 1]]
              else
                [Losers["barrage", 1]]
              end

    placement_tree(prefix: "ko", key: "ko", label: "Consolante",
                   sources: sources, pairing: :seeded,
                   size: next_power_of_two(ko_entrants), offset: ok_size + 1,
                   entrants: ko_entrants)
  end

  # n 1ers de poule + n vainqueurs de barrage, arrondi à la puissance de 2.
  def ok_size = next_power_of_two(@pool_count * 2)

  def ko_entrants = @players_per_pool >= 4 ? @pool_count * 2 : @pool_count

  # ── Mode intégral : un seul tableau, aucun barrage, aucun ex æquo ────────────
  # Tout le monde entre dans le même tableau, classé par POSITION DE POULE : les
  # 1ers de poule prennent les têtes de série, puis les 2es, etc. (`:pool_rank`).
  # Ni serpentin ni classement individuel — l'app n'a pas de classement officiel,
  # et le rang de poule est le seul ordre que le tournoi ait réellement produit.
  def integral_nodes
    placement_tree(prefix: "ok", key: "ok", label: "Tableau final",
                   sources: (1..@players_per_pool).map { |rank| PoolQualifiers[rank] },
                   pairing: :pool_rank,
                   size: next_power_of_two(@player_count), offset: 1,
                   entrants: @player_count)
  end

  # ── La récursion ────────────────────────────────────────────────────────────
  # Un tableau de `size` places attribuant `offset`..`offset + size - 1`, PLUS
  # tous les nœuds de classement de ses perdants. `prefix` (« ok » / « ko »)
  # préfixe les clés des descendants : c'est ce qui garantit qu'un mini-tableau
  # du tableau final ne collisionne pas avec son homologue de la consolante.
  def placement_tree(prefix:, key:, label:, sources:, pairing:, size:, offset:, entrants:)
    root = Node.new(key: key, **coords(key), label: label, kind: :elimination,
                    sources: sources, pairing: pairing,
                    places: [offset, offset + size - 1], tie_at: nil,
                    size: size, entrants: entrants)

    # Le dernier tour est la finale du nœud : elle attribue `offset` et
    # `offset + 1`, il n'y a donc pas de nœud enfant pour ses perdants.
    children = (1...root.round_count).flat_map do |round|
      losers_node(prefix: prefix, parent_key: key, round: round,
                  group: size / (2**round), offset: offset)
    end

    [root] + children
  end

  # Les perdants du tour `round` : soit un palier d'ex æquo, soit un mini-tableau
  # qui rejoue intégralement les places concernées.
  def losers_node(prefix:, parent_key:, round:, group:, offset:)
    first = offset + group
    last  = first + group - 1
    key   = "#{prefix}:#{first}-#{last}"

    if group >= tie_from
      [Node.new(key: key, **coords(key), label: "#{ordinal(first)}s ex æquo", kind: :tie,
                sources: [Losers[parent_key, round]], pairing: nil,
                places: [first, last], tie_at: first, size: group, entrants: group)]
    else
      placement_tree(prefix: prefix, key: key, label: placement_label(first, last),
                     sources: [Losers[parent_key, round]], pairing: :carry_over,
                     size: group, offset: first, entrants: group)
    end
  end

  # ── Clé → coordonnées en base ───────────────────────────────────────────────
  # Les trois tableaux « principaux » occupent leur propre phase sur la branche
  # « main » ; tous les mini-tableaux de classement partagent la phase
  # `classification` et se distinguent par leur branche, qui EST leur clé.
  def coords(key)
    case key
    when "barrage" then { phase: "barrage",     branch: TournamentRound::MAIN_BRANCH }
    when "ok"      then { phase: "bracket",     branch: TournamentRound::MAIN_BRANCH }
    when "ko"      then { phase: "consolation", branch: TournamentRound::MAIN_BRANCH }
    else                { phase: "classification", branch: key }
    end
  end

  # ── Libellés ────────────────────────────────────────────────────────────────
  def placement_label(first, last)
    return "Match pour la #{ordinal(first)} place" if last - first == 1

    "Places #{first} à #{last}"
  end

  def ordinal(number) = number == 1 ? "1er" : "#{number}e"

  # Plus petite puissance de 2 ≥ `count` (au minimum 2).
  def next_power_of_two(count)
    power = 1
    power *= 2 while power < count
    [power, 2].max
  end
end
