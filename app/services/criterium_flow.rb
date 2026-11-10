# ── Service CriteriumFlow ─────────────────────────────────────────────────────
# Moteur du format « Critérium Fédéral » (FFTT). MATÉRIALISE en TournamentRound la
# topologie déclarée par CriteriumStructure : barrages, tableau final (« OK »),
# consolante (« KO ») et mini-tableaux de classement.
#
# ── Un réconciliateur, pas une machine à états ─────────────────────────────────
# #advance! ne demande jamais « où en est-on ? ». Il parcourt TOUS les nœuds
# déclarés, recalcule ceux qui devraient exister d'après les tours déjà terminés,
# et ne crée que ce qui manque. Deux propriétés en découlent, indispensables :
#
#   • idempotence — double-clic, rechargement Turbo, appels concurrents : le
#     deuxième appel ne crée rien. L'index unique (tournoi, phase, branche, numéro)
#     est le garde-fou de dernier recours, exactement comme pour les journées de poule.
#   • déterminisme — aucun `shuffle`, `rand` ni `Time.now` ici. `draw_order`, tiré
#     une fois au lancement, est la seule source d'aléa. C'est la condition pour
#     qu'une correction de score (Lot 8) puisse détruire l'aval et le reconstruire
#     à l'identique.
#
# ── Pourquoi une boucle sur les nœuds, et pas un enchaînement écrit à la main ──
# Le format compte jusqu'à 11 tableaux (tableau final, consolante, et leurs
# classements imbriqués). Les câbler un par un demanderait de réécrire dans ce
# fichier les places, les sources et les appariements que CriteriumStructure
# déclare déjà — deux descriptions du règlement à garder en phase. Ici, un nœud
# n'a que deux états possibles : pas encore ouvert (ses sources sont-elles
# résolues ?) ou en cours (son dernier tour est-il terminé ?). Ajouter un nœud à
# la structure ne demande AUCUNE modification de ce service.
#
# Point d'entrée unique : #advance!. Il n'y a pas de #start! — le premier appel
# (poules terminées, rien en phase finale) crée les barrages, les suivants font
# progresser. C'est le même code.
class CriteriumFlow
  include RoundRobinStats

  # ── Une case du premier tour d'un tableau nourri par les barrages ───────────
  # Le tableau final et la consolante ne s'ouvrent plus « à la fin des barrages » :
  # leurs cases sont FIGÉES dès que les barrages existent, et chaque match naît dès
  # que son barrage est joué (cf. #sync_slotted_node!). Une case est donc :
  #   • un joueur déjà connu (`player`) — un 1er ou un 4e de poule ;
  #   • ou une promesse (`barrage` + `camp`) — « le vainqueur (ou le perdant) de
  #     tel barrage », résolue quand ce barrage est joué ;
  #   • ou une attente (`origin`) — « le perdant du match N de tel tour », pour un
  #     mini-tableau de classement dont le match nourricier n'est pas encore joué
  #     (cf. #loser_slots). `origin` = Feeder, qui sert aussi au libellé de la vue.
  #     Une case de perdant résolue redevient un `known`, qui garde son `origin`.
  Slot = Data.define(:player, :barrage, :camp, :origin) do
    def self.known(player, origin = nil) = new(player: player, barrage: nil, camp: nil, origin: origin)
    def self.from(barrage, camp)         = new(player: nil, barrage: barrage, camp: camp, origin: nil)
    def self.awaiting(origin)            = new(player: nil, barrage: nil, camp: :loser, origin: origin)

    # Une attente n'a ni joueur ni barrage : elle est en suspens par définition.
    def pending? = player.nil? && !barrage&.decided?

    # Le joueur qui occupe la case (nil tant que le barrage n'est pas joué).
    def occupant = player || (barrage.public_send(camp) unless pending?)

    # TOUTES les poules dont l'occupant peut venir. Une case de barrage en porte
    # deux : on ignore encore qui gagnera, donc l'évitement « même poule » doit
    # tenir quel que soit le résultat — sinon la case bougerait après le barrage.
    # (Une attente n'est jamais déplacée : les mini-tableaux n'évitent pas la même
    # poule, cf. #entrants_for — d'où la liste vide.)
    def pools
      return [player.pool] if player
      return barrage.players.map(&:pool) if barrage

      []
    end
  end

  # ── Provenance d'une case de mini-tableau ───────────────────────────────────
  # « Le perdant du match `position` (0-based) du tour `round` du tableau `key` ».
  # `round_count` = nombre de tours de ce tableau : c'est ce qui permet à la vue de
  # dire « 8e de finale 3 » plutôt que « tour 1, match 3 » (cf.
  # TournamentsHelper#bracket_slot_label).
  Feeder = Data.define(:key, :round, :position, :round_count)

  def initialize(tournament)
    @tournament = tournament
  end

  # Fait avancer le tournoi d'un cran. Renvoie le tour créé, ou le tour en cours
  # s'il n'y avait rien à créer (contrat de PoolBuilder#next_round!).
  def advance!
    ActiveRecord::Base.transaction do
      # Les classements de poule sont memoïsés sur le tournoi. Ce service peut être
      # appelé APRÈS une correction de score sur la même instance (cf.
      # TournamentMatchesController#apply_correction!) : sans cette purge, il
      # apparierait le tableau final sur un classement périmé alors que les
      # barrages, eux, viennent d'être reconstruits sur le classement neuf.
      @tournament.reset_standings!
      @standings = nil
      @layouts   = nil

      close_finished_rounds!

      created = [ensure_barrage!, *sync_nodes!].compact
      sync_qualified!
      complete_if_finished!(created)

      created.last || current_final_round
    end
  end

  # ── Correction d'un score DANS la phase finale (Lot 8) ──────────────────────
  # Corriger un quart de finale n'invalide pas la consolante : elle se joue en
  # parallèle, avec d'autres joueurs. Détruire toute la phase finale (ce que fait
  # une correction en POULE, où le classement de départ change et où tout est donc
  # caduc) y effacerait des scores encore parfaitement valides.
  #
  # On cherche donc les tours DEVENUS FAUX — ceux dont les joueurs réels ne sont
  # plus ceux que la structure produirait aujourd'hui — et on ne détruit que leur
  # AVAL STRUCTUREL (#destroy_downstream!) : les tours suivants du même tableau et
  # les mini-tableaux nés de ces tours. #advance! reconstruit ensuite : il est
  # déterministe, il retombe à l'identique sur tout ce que la correction n'a pas
  # touché.
  #
  # ⚠️ Pas « tout tour d'`id` supérieur » : depuis que les mini-tableaux de
  # classement naissent au fil de l'eau, le 5e-8e est créé AVANT les quarts.
  # Corriger un 8e (dont le perdant change) aurait alors détruit les quarts déjà
  # joués, qui n'ont rien à voir. `id` reste en revanche un ordre causal fiable
  # pour filtrer `from` : un tour n'est jamais créé avant SES sources (cf.
  # #loser_slots).
  #
  # Une boucle, pas une recherche unique : une correction change à la fois un
  # vainqueur (le tour suivant devient faux) ET un perdant (le mini-tableau de
  # classement devient faux), deux aval distincts.
  #
  # `from` = le tour corrigé lui-même : lui n'est jamais périmé (ses joueurs n'ont
  # pas changé, seul le vainqueur a changé), et l'exclure garantit qu'on ne détruit
  # jamais le tour qu'on vient d'éditer.
  def reconcile!(from: nil)
    ActiveRecord::Base.transaction do
      @tournament.reset_standings!
      @standings = nil
      @layouts   = nil

      while (stale = first_stale_round(after: from))
        destroy_downstream!(*stale)
        @layouts = nil
      end

      advance!
    end
  end

  # Ordre de force inter-poules (cf. #by_strength), exposé pour le classement
  # final (TournamentStandings#tail_groups) : un joueur qu'aucun tableau ne classe
  # doit être ordonné selon la MÊME clé que celle qui a seedé les tableaux —
  # points-parties par match, puis quotients — et non selon Tournament#rank_key,
  # qui compare des différentiels.
  def rank_by_strength(players) = by_strength(players)

  # Le premier tour d'un tableau posé case par case, position par position :
  # [[Slot|nil, Slot|nil], …] (nil = bye). Exposé pour les vues, qui annoncent
  # « Vainqueur X / Y » ou « Perdant 8e de finale 3 » sur les cases dont le match
  # n'existe pas encore.
  # nil si le tableau n'est pas posé case par case, ou si sa disposition n'est pas
  # encore connue (barrages pas créés, tour source pas encore en base).
  def first_round_slots(key)
    node = structure.node(key)
    node && laid_out?(node) ? layout(node) : nil
  end

  private

  def structure = @structure ||= @tournament.criterium_structure

  # ── Résolution des entrants d'un nœud ───────────────────────────────────────
  # Les joueurs qui entrent dans un nœud, dans l'ordre de tête de série.
  #
  # Renvoie [] tant que les sources ne sont pas jouées.
  #
  # Ne sert plus qu'aux tableaux construits D'UN BLOC à partir des poules (le
  # classement intégral). Tous les autres sont posés case par case (cf. #layout,
  # #sync_slotted_node!) : le tableau final et la consolante au fil des barrages,
  # les mini-tableaux de classement au fil des matchs de leur tableau parent.
  def entrants_for(node)
    groups = node.sources.map { |source| resolve(source) }

    case node.pairing
    # Classement intégral : les sources sont les rangs de poule dans l'ordre (les
    # 1ers, puis les 2es…), donc `flatten` EST déjà l'ordre de tête de série voulu.
    # On protège les 1ers de poule comme dans le tableau final : l'appariement
    # miroir les place alors en moitiés opposées, et aucun ne rencontre un autre 1er
    # au premier tour.
    when :pool_rank then avoid_own_pool_first_round(groups.flatten, protected_count: groups.first.size)
    else                 by_strength(groups.flatten)
    end
  end

  # ── Barrages ────────────────────────────────────────────────────────────────
  # Les 2es de poule contre les 3es, croisés. Nœud de TRANSIT : les vainqueurs
  # montent au tableau final, les perdants descendent en consolante. C'est le seul
  # nœud dont les DEUX camps continuent, d'où son traitement à part.
  def ensure_barrage!
    # Toutes les variantes n'ont pas de barrages : le classement intégral envoie
    # tout le monde dans un tableau unique, et une poule unique n'a aucune phase
    # finale. C'est la structure qui tranche — sans cette garde, un 2e et un 3e de
    # poule existant suffiraient à en fabriquer (cf. Tournament#criterium_mode).
    return nil if structure.node("barrage").blank?
    return nil if @tournament.barrage_rounds.exists?
    return nil unless pools_complete?

    pairs = barrage_pairs
    return nil if pairs.empty?

    round = create_round!(phase: "barrage", number: 1)
    pairs.each_with_index { |(player_a, player_b), position| build_match!(round, player_a, player_b, position) }
    round
  rescue ActiveRecord::RecordNotUnique
    # Deux requêtes concurrentes ont tenté de créer le même tour : l'index unique
    # a tranché, on renvoie celui qui a gagné.
    @tournament.barrage_rounds.first
  end

  # Appariement croisé. Les 2es par force DÉCROISSANTE face aux 3es par force
  # CROISSANTE : le meilleur 2e affronte le plus faible 3e, ce qui récompense le
  # classement de poule. Puis réparation des collisions « même poule ».
  #
  # Les deux listes n'ont pas toujours la même longueur, et le camp en surnombre
  # prend alors un bye (build_match! le fait monter au tableau final d'office) :
  #   • moins de 3es — une poule n'en a pas (poule de 2, effectif « Libre ») ;
  #   • moins de 2es — un 2e a abandonné le tournoi (cf. #qualifiers_at). Le bye
  #     revient au 3e le plus FORT, dernier de la liste croissante : c'est lui qui
  #     aurait affronté le 2e le plus faible.
  def barrage_pairs
    seconds = qualifiers_at(2)
    thirds  = qualifiers_at(3).reverse # déjà triés par force décroissante → croissante

    avoid_same_pool(seconds, thirds)
  end

  # Échange les 3es entre eux jusqu'à ce qu'aucun match n'oppose deux joueurs de la
  # même poule. Une solution existe toujours dès 2 poules (chaque poule ne fournit
  # qu'un 2e et qu'un 3e), et le balayage est déterministe — pas d'aléa, donc
  # reproductible à l'identique après correction.
  def avoid_same_pool(seconds, thirds)
    # Aligne les longueurs en complétant la liste la plus COURTE avec des nil
    # (= bye). Surtout ne pas tronquer la plus longue : `seconds.zip(thirds)`
    # faisait disparaître du tournoi le 3e le plus fort quand un 2e était parti.
    size = [seconds.size, thirds.size].max
    seconds += [nil] * (size - seconds.size)
    thirds += [nil] * (size - thirds.size)

    seconds.each_index do |i|
      next unless same_pool?(seconds[i], thirds[i])

      swap = seconds.each_index.find do |j|
        j != i && !same_pool?(seconds[i], thirds[j]) && !same_pool?(seconds[j], thirds[i])
      end
      thirds[i], thirds[swap] = thirds[swap], thirds[i] if swap
    end

    seconds.zip(thirds)
  end

  def same_pool?(player_a, player_b)
    player_a.present? && player_b.present? && player_a.pool == player_b.pool
  end

  # ── Les tableaux, pilotés par la structure ──────────────────────────────────
  # Tous les nœuds jouables, dans l'ordre de dépendance (un tableau avant les
  # mini-tableaux nés de ses perdants). Seuls les barrages sont écartés : ils ont
  # leur propre chemin (#ensure_barrage!). Tout le reste est un tableau à jouer,
  # jusqu'au dernier match de classement.
  def playable_nodes = structure.nodes.reject(&:transit?)

  def sync_nodes! = playable_nodes.map { |node| sync_node!(node) }

  # Deux familles de tableaux :
  #   • posés CASE PAR CASE (#laid_out?) — tableau final, consolante et
  #     mini-tableaux de classement : leur premier tour est figé d'avance et se
  #     remplit au fil des résultats (cf. #sync_slotted_node!) ;
  #   • construits D'UN BLOC — le tableau unique du classement intégral, ouvert
  #     quand les poules sont finies.
  #
  # Aucune garde de complétude sur le dernier tour : c'est le builder qui décide,
  # match par match, ce qui est créable — un quart naît dès que ses deux huitièmes
  # sont joués (cf. BracketBuilder en mode incrémental), sans attendre les autres.
  # #advance! renvoie nil quand il n'a rien créé, y compris quand le tableau a
  # atteint sa finale.
  def sync_node!(node)
    return sync_slotted_node!(node) if laid_out?(node)
    return open_node!(node) if rounds_of(node).empty?

    builder_for(node).advance!
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # ── Tableaux posés case par case : au fil de l'eau ──────────────────────────
  # Demande des joueurs : un match doit pouvoir se jouer dès que SES deux
  # adversaires sont connus, sans attendre le reste du tour qui les a produits.
  #   • tableau final / consolante : dès que SON barrage est fini ;
  #   • mini-tableau de classement : dès que SES deux matchs nourriciers du
  #     tableau parent sont joués (le perdant du 8e n°1 contre celui du 8e n°8).
  #
  # Le premier tour est donc créé dès que sa disposition est connue (#layout),
  # avec toutes ses cases figées, et chaque appel y pose les matchs devenus
  # connus. Les tours suivants avancent ensuite comme d'habitude (incrémental).
  #
  # ⚠️ C'est ce qui interdit d'apparier les entrants APRÈS coup, comme avant : la
  # place d'un joueur ne doit dépendre ni de son identité ni de l'issue des
  # autres matchs, sinon un match déjà posé se retrouverait à la mauvaise case
  # quand le suivant se termine.
  #
  # Tableau tiré AVANT ce mode (mini-tableau ouvert d'un bloc, en cours au
  # déploiement) : toutes ses positions sont déjà posées, on n'y ajoute rien. Sa
  # disposition peut différer de celle que #layout produirait aujourd'hui (un
  # forfait y était resserré), et y poser des positions supplémentaires ferait
  # jouer deux fois les mêmes joueurs.
  def sync_slotted_node!(node)
    pairs = layout(node)
    return nil if pairs.nil?

    builder = builder_for(node)
    first   = builder.place_first_round!(pairs.map { |pair| resolve_pair(pair) }) unless first_round_full?(node)
    builder.advance! || first
  end

  def first_round_full?(node)
    round = rounds_of(node).first
    return false if round.nil?

    round.tournament_matches.size >= (round.expected_matches || 0)
  end

  # Ce tableau est-il posé case par case ? Structurel (la structure seule
  # tranche), pour que le chemin choisi ne dépende pas de l'état d'avancement.
  def laid_out?(node) = barrage_fed?(node) || losers_fed?(node)

  # Nourri par les barrages (nœud de transit) : tableau final et consolante.
  def barrage_fed?(node)
    node.sources.any? do |source|
      !source.is_a?(CriteriumStructure::PoolQualifiers) && structure.node(source.key)&.transit?
    end
  end

  # Mini-tableau de classement : les perdants d'un tour d'un tableau parent.
  def losers_fed?(node)
    node.pairing == :carry_over && !barrage_fed?(node) &&
      node.sources.all?(CriteriumStructure::Losers)
  end

  # ── Disposition du premier tour ─────────────────────────────────────────────
  # [[Slot|nil, Slot|nil], …] par position (nil = bye), ou nil tant qu'elle n'est
  # pas connue. Memoïsée pour la passe : un mini-tableau relit la disposition de
  # son parent, qui relit celle du sien, jusqu'au tableau final.
  def layout(node)
    @layouts ||= {}
    return @layouts[node.key] if @layouts.key?(node.key)

    slots = slots_of(node)
    @layouts[node.key] = slots.present? ? slot_pairs(slots) : nil
  end

  def slots_of(node)
    if barrage_fed?(node)
      ordered_slots(node) if pools_complete? && @tournament.barrage_rounds.exists?
    elsif losers_fed?(node)
      loser_slots(node.sources.first)
    end
  end

  # ── Cases d'un mini-tableau de classement ───────────────────────────────────
  # Une case par match du tour source, dans l'ordre des positions — exactement
  # l'ordre dans lequel l'ancien mode rangeait les perdants. L'appariement miroir
  # (#slot_pairs) les reprend en moitiés opposées du tableau parent : deux joueurs
  # qui s'y sont déjà rencontrés ne se retrouvent pas immédiatement.
  #
  # ⚠️ ORDRE CAUSAL : aucune case tant que le tour source n'existe pas en base.
  # #reconcile! détruit « tout tour d'`id` ≥ le tour périmé » en supposant qu'un
  # tour est toujours créé APRÈS ses sources. Un 5e-8e créé avant les quarts
  # échapperait à la détection et garderait des joueurs qui n'y ont plus droit.
  #
  # Les byes STRUCTURELS du premier tour (case sans adversaire, effectif ≠
  # puissance de 2) n'ont pas de perdant : ils ne fournissent aucune case, comme
  # avant. Un bye né d'un FORFAIT, lui, garde sa case (cf. #loser_slot).
  #
  # Aucune case non plus quand le tour source est la FINALE du parent (un seul
  # match) : TournamentStandings#final_groups y attribue déjà la place du perdant,
  # le faire rejouer le compterait deux fois au classement.
  def loser_slots(source)
    parent = structure.node(source.key)
    round  = parent && rounds_of(parent).find { |r| r.number == source.round }
    width  = round && first_round_width(parent)
    return [] if width.nil?

    count = width / (2**(source.round - 1))
    return [] if count <= 1

    round_count = Integer(Math.log2(width * 2))
    matches     = round.tournament_matches.index_by(&:position)
    positions   = (0...count).reject { |position| source.round == 1 && structural_bye?(parent, position) }

    positions.map do |position|
      origin = Feeder[parent.key, source.round, position, round_count]
      loser_slot(parent, matches[position], origin)
    end
  end

  # Nombre de positions du premier tour d'un tableau : sa disposition s'il est
  # posé case par case, sinon son premier tour en base (construit d'un bloc).
  def first_round_width(node)
    return layout(node)&.size if laid_out?(node)

    first = rounds_of(node).first
    first && (first.expected_matches || first.tournament_matches.size)
  end

  def structural_bye?(node, position)
    return layout(node)[position].include?(nil) if laid_out?(node)

    rounds_of(node).first.tournament_matches.find { |m| m.position == position }&.is_bye
  end

  # Le perdant d'un match nourricier, ou une attente s'il n'est pas joué.
  #
  # ⚠️ Bye né d'un forfait (un joueur parti AVANT que son match soit posé, cf.
  # #resolve_pair, BracketBuilder#pair_players) : il n'y a pas de perdant, mais la
  # case ne peut pas rester vide — deux cases vides face à face formeraient une
  # position où aucun match n'est posable, le tour ne serait jamais complet et le
  # tournoi ne se terminerait jamais. L'occupant est donc le PARTANT lui-même :
  # #resolve_pair donne alors un bye à son adversaire (ou un match en forfait si
  # les deux sont partis), la même règle que partout ailleurs.
  def loser_slot(parent, match, origin)
    return Slot.awaiting(origin) unless match&.status == "completed"
    return Slot.known(match.loser, origin) if match.loser

    Slot.known(absentee(parent, origin, match), origin)
  end

  # Le joueur qui aurait dû affronter le bénéficiaire d'un bye : au premier tour,
  # l'autre occupant de la case ; au-delà, l'autre vainqueur des deux matchs
  # nourriciers (le match `p` du tour n+1 réunit les vainqueurs de 2p et 2p+1).
  def absentee(parent, origin, match)
    expected =
      if origin.round == 1
        Array(layout(parent)&.dig(origin.position)).map { |slot| slot&.occupant }
      else
        feeders = rounds_of(parent).find { |r| r.number == origin.round - 1 }&.tournament_matches.to_a
        feeders.select { |m| [origin.position * 2, (origin.position * 2) + 1].include?(m.position) }.map(&:winner)
      end

    expected.compact.find { |player| player != match.player_a }
  end

  # Les cases du premier tour, dans l'ordre de tête de série.
  #
  # Tableau final (`:exempt_first`) : les 1ers de poule par force gardent les têtes
  # de série hautes, puis « vainqueur du barrage N » dans l'ordre des barrages.
  #
  # Consolante (`:seeded`) : « perdant du barrage N » d'abord — ce sont des 2es et
  # des 3es, au-dessus de n'importe quel 4e —, puis les 4es par force. Un barrage
  # sans adversaire (bye) n'a pas de perdant, il ne fournit donc aucune case.
  #
  # Puis réparation « même poule », calculée sur les poules POSSIBLES de chaque case.
  #
  # ⚠️ Les joueurs partis ne sont PAS écartés ici, contrairement à #resolve : une
  # case ne doit jamais disparaître, sinon toutes les suivantes glisseraient d'un
  # cran sous des matchs déjà posés. Un partant laisse sa case, et son adversaire
  # y prend un bye (#resolve_pair).
  def ordered_slots(node)
    barrages = @tournament.barrage_rounds.first&.tournament_matches&.sort_by(&:position) || []

    known, promised = node.sources.partition { |source| source.is_a?(CriteriumStructure::PoolQualifiers) }
    known    = known.flat_map { |source| by_strength(pool_qualifiers(source.rank)).map { |tu| Slot.known(tu) } }
    promised = promised.flat_map do |source|
      camp = source.is_a?(CriteriumStructure::Winners) ? :winner : :loser
      fed  = camp == :loser ? barrages.reject(&:is_bye) : barrages
      fed.map { |match| Slot.from(match, camp) }
    end

    if node.pairing == :seeded
      # Seuls les 4es bougent : déplacer une case de perdant ferait se croiser deux
      # 4es au premier tour. Sans 4e (poules de 3), tout le monde est déplaçable.
      avoid_own_pool_first_round(promised + known, protected_count: known.any? ? promised.size : 0)
    else
      avoid_own_pool_first_round(known + promised, protected_count: known.size)
    end
  end

  # Les cases, appariées comme BracketBuilder apparie ses entrants (seeding 1 vs N).
  # nil = bye (case au-delà de l'effectif).
  def slot_pairs(slots)
    BracketBuilder.seed_order(next_power_of_two(slots.size))
                  .each_slice(2)
                  .map { |seed_a, seed_b| [slots[seed_a - 1], slots[seed_b - 1]] }
  end

  # Les deux joueurs d'une position, ou nil si un barrage reste à jouer.
  # Un partant est remplacé par un bye, comme BracketBuilder#pair_players le fait
  # aux tours suivants — sauf si les DEUX sont partis : un match en forfait vaut
  # mieux qu'une branche gelée pour toujours.
  def resolve_pair(pair)
    return nil if pair.compact.any?(&:pending?)

    raw     = pair.map { |slot| slot&.occupant }
    playing = raw.map { |player| player&.withdrawn? ? nil : player }

    playing.compact.empty? ? raw : playing
  end

  # Premier tour d'un tableau construit d'un bloc (classement intégral), ouvert
  # quand TOUTES ses sources sont jouées.
  def open_node!(node)
    return nil unless sources_ready?(node)

    entrants = entrants_for(node)
    return nil if entrants.empty?

    builder_for(node, entrants).build!
  end

  # `owns_completion: false` : la finale du tableau final est souvent jouée alors
  # que la consolante et les matchs de classement tournent encore. C'est
  # #complete_if_finished! qui décide de la fin du tournoi, pas un tableau isolé.
  #
  # `persist_seeds` UNIQUEMENT pour le tableau final : `tournament_users.seed` est
  # une colonne unique par inscription, donc un second tableau écraserait les têtes
  # de série du premier. Les autres apparient sur l'ordre reçu (cf. BracketBuilder).
  # (Sans effet en mode standard : le tableau final y est posé case par case par
  # #place_first_round!, qui n'écrit pas de tête de série — un vainqueur de
  # barrage n'est pas connu au moment où sa case est réservée.)
  #
  # `finalists` n'est nécessaire qu'au premier tour (#build!) ; #advance! dérive ses
  # entrants des vainqueurs du tour précédent.
  #
  # `incremental: true` : le Critérium s'étale dans le temps, un match doit donc
  # être jouable dès que ses deux adversaires sont connus (cf. BracketBuilder).
  def builder_for(node, entrants = nil)
    BracketBuilder.new(@tournament, finalists: entrants, phase: node.phase, branch: node.branch,
                                    persist_seeds: node.key == "ok", owns_completion: false,
                                    incremental: true)
  end

  # ── État « qualifié » ───────────────────────────────────────────────────────
  # Les qualifiés du tournoi sont les joueurs du 1er tour du tableau final, et
  # EUX SEULS. Les perdants de barrage ne sont PAS éliminés : ils rejoignent la
  # consolante, donc ils restent `active`.
  #
  # Dérivé à chaque #advance! depuis les tours RÉELLEMENT en base, et non posé une
  # fois à l'ouverture du tableau : une correction de score détruit puis
  # reconstruit la phase finale (cf. #reconcile!, TournamentMatchesController), et
  # un joueur qui n'y entre plus garderait sinon son icône « Qualifié ».
  # `withdrawn` est terminal : jamais écrasé, dans un sens comme dans l'autre.
  def sync_qualified!
    node = structure.node("ok")
    return if node.blank?

    first_round = rounds_of(node).first
    ids = first_round ? first_round.tournament_matches.flat_map { |m| [m.player_a_id, m.player_b_id] }.compact : []
    players = @tournament.tournament_users.players

    players.qualified.where.not(id: ids).update_all(state: "active")
    players.where(id: ids).where(state: "active").update_all(state: "qualified")
  end

  def rounds_of(node)
    @tournament.tournament_rounds.where(phase: node.phase, branch: node.branch).ordered
  end

  # ── Détection de l'aval périmé (cf. #reconcile!) ────────────────────────────
  # Le premier tour, dans l'ordre causal, dont les joueurs ne sont plus les bons :
  # [nœud, tour], ou nil.
  def first_stale_round(after: nil)
    rounds = final_rounds
    rounds = rounds.select { |_node, round| round.id > after.id } if after

    rounds.find { |node, round| stale?(node, round) }
  end

  # Détruit le tour `round` d'un tableau, ses tours suivants, et récursivement
  # tous les tableaux qui se nourrissent d'un de ces tours. La boucle de
  # #reconcile! termine : chaque passage détruit au moins le tour périmé trouvé.
  def destroy_downstream!(node, round)
    rounds_of(node).where(number: round.number..).destroy_all

    dependants_of(node.key, round.number).each do |child|
      first = rounds_of(child).first
      destroy_downstream!(child, first) if first
    end
  end

  # Les tableaux nourris par le tour `number` (ou un suivant) du tableau `key`.
  def dependants_of(key, number)
    playable_nodes.select do |child|
      child.sources.any? do |source|
        !source.is_a?(CriteriumStructure::PoolQualifiers) && source.key == key && source.round >= number
      end
    end
  end

  # Tous les tours jouables de la phase finale, ordre causal (= ordre des `id`).
  # Les barrages n'y figurent pas : ils naissent du classement des poules, qui ne
  # bouge pas quand on corrige un match de phase finale.
  def final_rounds
    playable_nodes.flat_map { |node| rounds_of(node).map { |round| [node, round] } }
                  .sort_by { |_node, round| round.id }
  end

  # Ce tour oppose-t-il encore les bons joueurs ?
  #
  # Premier tour d'un tableau : on compare des ENSEMBLES d'inscriptions, pas des
  # appariements. C'est suffisant là, et seulement là : l'ordre des entrants ne
  # dépend que du classement des poules (inchangé par cette correction), donc un
  # vainqueur qui change change forcément QUI entre, jamais seulement dans quel ordre.
  #
  # Entrants attendus vides = sources non résolues (le tour source a été détruit,
  # ou n'est plus complet) : on ne conclut rien plutôt que de détruire à l'aveugle.
  # Ce tour-là sera de toute façon repris par le tour source, forcément plus ancien.
  #
  # ── Tours suivants : POSITION PAR POSITION, jamais en ensemble ───────────────
  # Un tour construit au fur et à mesure a des TROUS (cf. BracketBuilder#advance!
  # en mode incrémental) : la demi-finale née des quarts 1-2 existe seule, avec
  # 2 joueurs, alors que le tour précédent en annonce 4. Une comparaison
  # d'ensembles la déclarerait donc périmée et la détruirait — avec son score — à
  # la moindre correction, exactement ce que #reconcile! s'interdit de faire.
  #
  # La règle positionnelle est de toute façon la plus juste, même sans progression
  # anticipée : le match de position `i` du tour n+1 oppose les vainqueurs des
  # matchs `2i` et `2i+1` du tour n. Corriger le quart 3 ne périme donc plus la
  # demi-finale née des quarts 1 et 2.
  def stale?(node, round)
    return stale_first_round?(node, round) if round.number == 1

    winners = winners_by_position(node.key, round.number - 1)

    round.tournament_matches.any? do |match|
      expected = [winners[match.position * 2], winners[(match.position * 2) + 1]].compact.to_set
      # Aucun vainqueur connu en amont de cette position : source détruite ou tour
      # source redevenu incomplet. On ne conclut rien — le tour source, forcément
      # plus ancien, reprendra la main.
      next false if expected.empty?

      expected != [match.player_a_id, match.player_b_id].compact.to_set
    end
  end

  # ⚠️ Les joueurs partis sont ignorés DES DEUX CÔTÉS. #resolve les écarte des
  # entrants attendus — c'est juste pour OUVRIR un tableau, pas pour juger un
  # tableau déjà tiré : un joueur qui abandonne APRÈS le tirage y figure
  # légitimement. Sans cette symétrie, son départ rendait le tour « périmé », et la
  # correction suivante d'un barrage détruisait le tableau final et tous ses scores.
  def stale_first_round?(node, round)
    return stale_slotted_round?(node, round) if laid_out?(node)

    expected = expected_entrants(node, round.number).to_set(&:id)
    return false if expected.empty?

    expected != participants_of(round) - withdrawn_ids
  end

  # Premier tour posé case par case. Il a des trous tant que des barrages (ou,
  # pour un mini-tableau, des matchs du tableau parent) restent à jouer : exiger
  # l'égalité des ensembles le déclarerait périmé à tort.
  # On vérifie donc l'INCLUSION — chaque joueur déjà placé a-t-il encore le droit
  # d'être là ? Un barrage corrigé change de vainqueur : l'ancien n'est plus
  # ayant droit au tableau final (il l'est devenu en consolante), et le tour est
  # périmé dans les deux tableaux.
  #
  # ⚠️ Volontairement indépendant de la DISPOSITION des cases : un tableau tiré
  # avant ce mode (apparié après les barrages, par force) a une autre disposition
  # que celle que #layout produirait aujourd'hui — un mini-tableau ouvert d'un
  # bloc aussi, quand un forfait y a été resserré. Le juger case par case le
  # détruirait — avec ses scores — à la première correction venue.
  # Partants ignorés, comme ci-dessus. Disposition inconnue (tour source
  # détruit) : on ne conclut rien, le tour source plus ancien reprendra la main.
  def stale_slotted_round?(node, round)
    pairs = layout(node)
    return false if pairs.nil?

    entitled = pairs.flatten.compact.filter_map(&:occupant).to_set(&:id)

    !(participants_of(round) - withdrawn_ids).subset?(entitled)
  end

  def withdrawn_ids = @tournament.tournament_users.withdrawn.pluck(:id).to_set

  # {position => id du vainqueur} pour le tour `number` d'un nœud, SANS exiger que
  # le tour soit complet — c'est précisément ce qui permet de juger un tour aval
  # partiel. Les matchs non décidés sont simplement absents de la table.
  def winners_by_position(key, number)
    node  = structure.node(key)
    round = node && rounds_of(node).find { |r| r.number == number }
    return {} if round.blank?

    round.tournament_matches.each_with_object({}) do |match, index|
      winner = match.winner
      index[match.position] = winner.id if winner
    end
  end

  # Round 1 : les entrants du nœud. Tours suivants : les vainqueurs du précédent —
  # la même lecture que celle qui a servi à les créer.
  def expected_entrants(node, number)
    return entrants_for(node) if number == 1

    camp_of(node.key, number - 1, :winner)
  end

  def participants_of(round)
    round.tournament_matches.flat_map { |match| [match.player_a_id, match.player_b_id] }.compact.to_set
  end

  # ── Résolution des sources ──────────────────────────────────────────────────
  # Toutes les sources d'un nœud ont-elles livré leur contenu DÉFINITIF ?
  #
  # Un tour source jamais créé (parce que son tableau n'a pas assez d'entrants)
  # laisse le nœud fermé pour toujours, et c'est le comportement voulu : personne
  # n'y jouera, donc ses places ne seront pas attribuées.
  def sources_ready?(node)
    node.sources.all? do |source|
      case source
      when CriteriumStructure::PoolQualifiers then pools_complete?
      when CriteriumStructure::Winners, CriteriumStructure::Losers
        round_complete?(source.key, source.round)
      else false
      end
    end
  end

  def round_complete?(key, number)
    node  = structure.node(key)
    round = node && rounds_of(node).find { |r| r.number == number }

    round.present? && round.complete?
  end

  # ⚠️ Les joueurs déclarés forfait sont écartés ICI, à la source, et pas dans
  # #entrants_for : ce dernier mesure `groups.first.size` pour protéger les têtes
  # de série des 1ers de poule, un compte qui serait décalé par un filtrage plus
  # tardif. Filtrer ici couvre d'un coup PoolQualifiers, Winners et Losers, donc
  # #entrants_for ET #expected_entrants — la cohérence entre ce qu'on crée et ce
  # qu'on juge périmé est ainsi garantie, sans quoi #reconcile! boucderait.
  #
  # Conséquence voulue : un partant n'entre dans AUCUN tableau ouvert après son
  # forfait. Il reste là où il s'est arrêté (ses matchs déjà créés gardent leur
  # forfait), son adversaire du tour suivant prend un bye au lieu d'une victoire
  # par forfait, et le classement final le range en dernier faute de place jouée.
  def resolve(source)
    players = case source
              when CriteriumStructure::PoolQualifiers then qualifiers_at(source.rank)
              when CriteriumStructure::Winners        then camp_of(source.key, source.round, :winner)
              when CriteriumStructure::Losers         then camp_of(source.key, source.round, :loser)
              else []
              end

    players.reject(&:withdrawn?)
  end

  # Les vainqueurs (ou les perdants) du tour `number` d'un nœud, dans l'ordre des
  # matchs. [] si le tour n'existe pas ou n'est pas fini : c'est ce qui empêche
  # d'ouvrir un tableau avec des entrants incomplets.
  #
  # ⚠️ Les byes ne sont écartés que du côté PERDANTS : le « perdant » d'un bye
  # n'existe pas, mais son vainqueur, oui — c'est le joueur exempté, et il doit
  # continuer. Un barrage sans 3e de poule (poule incomplète) est un bye dont le 2e
  # monte d'office au tableau final ; l'écarter le ferait disparaître du tournoi.
  #
  # C'est aussi ce qui rend juste la formule des places : un tableau de 8 à 6
  # entrants n'envoie que 2 joueurs vers son mini-tableau 5e-8e, pas 4.
  def camp_of(key, number, camp)
    node  = structure.node(key)
    round = node && rounds_of(node).find { |r| r.number == number }
    return [] if round.blank? || !round.complete?

    matches = round.tournament_matches.sort_by(&:position)
    matches = matches.reject(&:is_bye) if camp == :loser

    matches.filter_map(&camp)
  end

  # Post-passe : écarter du premier tour deux joueurs de la même poule (ils
  # viennent de s'y affronter). `protected_count` = nombre d'entrants de tête qu'on
  # ne déplace PAS, pour ne pas défaire le seeding des 1ers de poule. Si aucun
  # échange ne résout la collision, on la laisse : le tableau doit exister, une
  # affiche imparfaite valant mieux qu'un blocage.
  #
  # Les entrants sont des joueurs OU des cases (Slot) : cf. #clash?.
  def avoid_own_pool_first_round(entrants, protected_count:)
    entrants = entrants.dup
    swappable = (protected_count...entrants.size).to_a

    first_round_pairs(entrants.size).each do |index_a, index_b|
      next unless clash?(entrants[index_a], entrants[index_b])

      # On déplace celui des deux qui n'est pas protégé.
      moving = swappable.include?(index_b) ? index_b : index_a
      other  = moving == index_b ? index_a : index_b

      target = swappable.find do |j|
        next false if j == moving

        # L'adversaire de la place visée peut être un bye (nil) : personne à heurter.
        partner = partner_of(j, entrants.size)

        !clash?(entrants[other], entrants[j]) &&
          (partner.nil? || !clash?(entrants[partner], entrants[moving]))
      end
      entrants[moving], entrants[target] = entrants[target], entrants[moving] if target
    end

    entrants
  end

  # Deux entrants risquent-ils de venir de la même poule ? Un joueur n'a qu'une
  # poule ; une case de barrage en a deux possibles (cf. Slot#pools), et la
  # collision doit être évitée quel que soit le vainqueur.
  def clash?(entrant_a, entrant_b)
    return false if entrant_a.nil? || entrant_b.nil?

    pools_of(entrant_a).intersect?(pools_of(entrant_b))
  end

  def pools_of(entrant) = entrant.is_a?(Slot) ? entrant.pools : [entrant.pool]

  # Les paires du premier tour, exprimées en INDEX dans le tableau des entrants
  # (BracketBuilder apparie sur l'index, pas sur la colonne `seed`). Les byes
  # (index hors effectif) sont écartés : ils n'opposent personne.
  def first_round_pairs(count)
    slots = next_power_of_two(count)
    BracketBuilder.new(@tournament).seed_order(slots)
                  .each_slice(2)
                  .filter_map do |seed_a, seed_b|
                    pair = [seed_a - 1, seed_b - 1]
                    pair if pair.all? { |index| index < count }
                  end
  end

  # L'adversaire de l'entrant d'index `index` au premier tour (nil = bye).
  def partner_of(index, count)
    pair = first_round_pairs(count).find { |a, b| [a, b].include?(index) }
    pair && (pair.first == index ? pair.last : pair.first)
  end

  # ── Fin de tournoi ──────────────────────────────────────────────────────────
  # Le tournoi n'est terminé que quand il n'y a plus RIEN à créer ni à jouer.
  #
  # `created.any?` est le cœur de la règle, et ce n'est pas une optimisation : ce
  # service étant une fonction pure de l'état, si un passage n'a rien créé et que
  # tout est joué, alors aucun passage ultérieur ne créera quoi que ce soit sans
  # nouveau score — c'est un point fixe. Sans cette garde, un tour intégralement
  # composé de byes (donc « terminé » à la création) ferait conclure le tournoi
  # alors que son tour suivant reste à générer.
  def complete_if_finished!(created)
    return if @tournament.completed?
    return if created.any?
    return unless ok_finished? # le champion doit être connu
    return unless @tournament.tournament_rounds.final_phase.all?(&:complete?)

    @tournament.update!(status: "completed")
  end

  # Le tableau final est-il allé jusqu'à sa finale (dernier tour = 1 seul match) ?
  #
  # Une poule unique (≤ 7 joueurs) n'a AUCUN tableau : exiger une finale y
  # laisserait le tournoi éternellement « en cours » alors que tout est joué et que
  # le classement de la poule a déjà désigné le vainqueur.
  def ok_finished?
    return true if structure.node("ok").blank?

    last = @tournament.bracket_rounds.last
    last.present? && last.complete? && last.tournament_matches.size == 1
  end

  # ── Lecture de l'état ───────────────────────────────────────────────────────
  def pools_complete?
    standings.any? && standings.values.all?(&:complete?)
  end

  # Les Nes de chaque poule, toutes poules confondues, triés par force.
  # C'est PoolStandings (règlement FFTT) qui décide du rang dans la poule.
  #
  # ⚠️ On n'écarte PAS le partant du classement de poule lui-même (PoolStandings
  # décide des qualifiés, et ses matchs sont joués) : on l'écarte de ceux qui
  # ENTRENT en phase finale. Un 2e de poule parti n'est donc pas apparié aux
  # barrages, et son adversaire y prend un bye — cf. #barrage_pairs, qui gère
  # déjà les `nil` par `zip`.
  def qualifiers_at(rank)
    by_strength(pool_qualifiers(rank).reject(&:withdrawn?))
  end

  # Les Nes de chaque poule, partants COMPRIS (cf. #ordered_slots).
  def pool_qualifiers(rank) = standings.values.filter_map { |pool| pool.qualifier(rank) }

  # Ordre de force inter-poules. Le règlement FFTT ne définit pas de classement
  # entre poules (il s'appuie sur le classement officiel des joueurs, que l'app
  # n'a pas) : on classe donc au RATIO des points-parties, et non à leur total.
  #
  # Pourquoi le ratio : un effectif impair produit des poules de tailles
  # différentes (17 joueurs → plan [3, 3, 3, 3, 3, 2]). Le 1er de la poule de 2
  # n'a disputé qu'UN match, celui d'une poule de 3 en a disputé deux : comparer
  # des totaux bruts, c'est classer sur le nombre d'adversaires reçus au tirage,
  # pas sur la performance. Le vainqueur de la poule de 2 serait toujours dernier
  # des 1ers de poule, donc toujours celui qu'on envoie jouer un tour de plus.
  # Le quotient est d'ailleurs déjà la façon dont le règlement départage À
  # L'INTÉRIEUR d'une poule (cf. PoolStandings#tiebreak_key) : on prolonge la même
  # logique entre poules.
  #
  # DÉTERMINISME préservé : aucun aléa, `draw_order` reste l'ultime départage —
  # c'est la condition pour qu'une correction de score reconstruise l'aval à
  # l'identique (cf. en-tête de ce fichier).
  def by_strength(players)
    keys = players.to_h { |tu| [tu.id, pool_strength_key(tu)] }
    # Les deux clés ne sont pas comparables entre elles (des ratios face à des
    # totaux) : dès qu'UN joueur du lot n'a pas de ligne de poule, on retombe sur
    # #rank_key pour TOUT le lot. Mélanger lèverait sur `sort_by`.
    return players.sort_by { |tu| @tournament.rank_key(tu) } if keys.value?(nil)

    players.sort_by { |tu| keys[tu.id] }
  end

  # Clé de force d'un joueur, normalisée par son nombre de matchs joués. nil si le
  # joueur n'a pas de ligne de poule exploitable — poule non renseignée, poule
  # reconstituée, ou aucun match joué (division par zéro).
  def pool_strength_key(tu)
    row = standings[tu.pool]&.row_for(tu)
    return nil if row.nil? || row.played.zero?

    [-row.points.fdiv(row.played),
     -quotient(row.sets_won, row.sets_lost),
     -quotient(row.points_won, row.points_lost),
     tu.draw_order.to_i]
  end

  # Quotient et non différence, comme PoolStandings : rien de concédé = avantage
  # maximal, 0/0 = 0.0. Jamais de ZeroDivisionError.
  def quotient(won, lost)
    return won.zero? ? 0.0 : Float::INFINITY if lost.zero?

    won.fdiv(lost)
  end

  def standings = @standings ||= @tournament.pool_standings

  # ── Écriture ────────────────────────────────────────────────────────────────
  # Passe en "completed" tout tour dont les matchs sont tous joués. PoolBuilder ne
  # le fait plus pour nous : #advance! court-circuite sa boucle habituelle.
  def close_finished_rounds!
    rounds = @tournament.tournament_rounds.where(phase: %w[pool] + Tournament::FINAL_PHASES)
    rounds.where.not(status: "completed").each do |round|
      round.update!(status: "completed") if round.complete?
    end
  end

  def create_round!(phase:, number:, branch: TournamentRound::MAIN_BRANCH)
    @tournament.tournament_rounds.create!(phase: phase, branch: branch, number: number,
                                          status: "in_progress")
  end

  # Le tour de phase finale le plus récent — valeur de retour par défaut d'#advance!
  # quand il n'y avait rien à créer.
  def current_final_round
    @tournament.tournament_rounds.final_phase.order(:id).last
  end

  def next_power_of_two(count)
    power = 1
    power *= 2 while power < count
    [power, 2].max
  end
end
