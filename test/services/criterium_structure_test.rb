require "test_helper"

# ── Tests CriteriumStructure ──────────────────────────────────────────────────
# Ce fichier est la PREUVE DE CONFORMITÉ au règlement FFTT : chaque plage de
# places assertée ici est un chiffre lu dans le document de référence
# (tennis-de-table-tournois-v2.html). Aucune base de données n'est touchée — la
# structure est une fonction pure de (nombre de poules, taille de poule, mode).
class CriteriumStructureTest < ActiveSupport::TestCase
  # ── 32 joueurs : 8 poules de 4, la configuration de référence du document ────

  test "8 poules de 4 déclare les 17 nœuds attendus" do
    keys = structure(pool_count: 8, players_per_pool: 4).nodes.map(&:key)

    assert_equal 17, keys.size
    assert_equal %w[barrage
                    ok ok:9-16 ok:13-16 ok:15-16 ok:11-12 ok:5-8 ok:7-8 ok:3-4
                    ko ko:25-32 ko:29-32 ko:31-32 ko:27-28 ko:21-24 ko:23-24 ko:19-20].sort,
                 keys.sort
  end

  test "8 poules de 4 : les plages de places du tableau final sont celles du règlement" do
    s = structure(pool_count: 8, players_per_pool: 4)

    # Tableau OK de 16 : la finale donne 1/2, puis 3/4, 5-8, 9-16 — et chacun de
    # ces mini-tableaux reclasse à son tour ses propres perdants.
    assert_equal [1, 16],  s.node("ok").places
    assert_equal [3, 4],   s.node("ok:3-4").places
    assert_equal [5, 8],   s.node("ok:5-8").places
    assert_equal [7, 8],   s.node("ok:7-8").places
    assert_equal [9, 16],  s.node("ok:9-16").places
    assert_equal [13, 16], s.node("ok:13-16").places
    assert_equal [15, 16], s.node("ok:15-16").places
    assert_equal [11, 12], s.node("ok:11-12").places
  end

  test "8 poules de 4 : les plages de places de la consolante sont celles du règlement" do
    s = structure(pool_count: 8, players_per_pool: 4)

    # Consolante : 17/18 pour sa finale, puis 19/20, 21-24, 25-32 — même arbre
    # que le tableau final, décalé de 16 places.
    assert_equal [17, 32], s.node("ko").places
    assert_equal [19, 20], s.node("ko:19-20").places
    assert_equal [21, 24], s.node("ko:21-24").places
    assert_equal [23, 24], s.node("ko:23-24").places
    assert_equal [25, 32], s.node("ko:25-32").places
    assert_equal [29, 32], s.node("ko:29-32").places
    assert_equal [31, 32], s.node("ko:31-32").places
    assert_equal [27, 28], s.node("ko:27-28").places
  end

  test "les perdants d'un 8e de finale rejouent pour les places 9 à 16" do
    s = structure(pool_count: 8, players_per_pool: 4)

    # Perdre son 8e n'attribue AUCUNE place : ça envoie dans un vrai tableau de 8,
    # qui se joue en 3 tours et reclasse lui-même ses perdants.
    node = s.node("ok:9-16")
    assert node.elimination?
    assert_equal "Places 9 à 16", node.label
    assert_equal 8, node.size
    assert_equal 3, node.round_count
    assert_equal [CriteriumStructure::Losers["ok", 1]], node.sources

    # Ses propres perdants descendent en 13-16, ses vainqueurs jouent 11-12 puis 9-10.
    assert_equal [CriteriumStructure::Losers["ok:9-16", 1]], s.node("ok:13-16").sources
    assert_equal [CriteriumStructure::Losers["ok:13-16", 1]], s.node("ok:15-16").sources
    assert_equal [CriteriumStructure::Losers["ok:9-16", 2]], s.node("ok:11-12").sources
  end

  test "aucun nœud n'attribue de place sans la faire jouer, quel que soit le mode" do
    [structure(pool_count: 8, players_per_pool: 4),
     structure(pool_count: 8, players_per_pool: 3),
     structure(pool_count: 4, players_per_pool: 4, mode: :integral, player_count: 16)].each do |s|
      s.nodes.reject(&:transit?).each do |node|
        # Un nœud qui couvre k places est un tableau de k places joué en log2(k)
        # tours : il n'existe aucun moyen de repartir une plage sans la disputer.
        assert node.elimination?, "#{node.key} n'est pas un tableau"
        assert_equal node.last_place - node.first_place + 1, node.size
        assert_operator node.round_count, :>=, 1
      end
    end
  end

  test "8 poules de 4 : 120 matchs, dont 4 de phase finale par joueur" do
    s = structure(pool_count: 8, players_per_pool: 4)

    pool_matches = 8 * 6 # round-robin d'une poule de 4 = 6 rencontres
    assert_equal 48, pool_matches
    assert_equal 8,  s.node("barrage").match_count

    # Un tableau de n places entièrement disputé coûte n/2 × log2(n) matchs :
    # 16/2 × 4 = 32, de chaque côté.
    assert_equal 32, s.nodes.select { |n| n.key.start_with?("ok") }.sum(&:match_count)
    assert_equal 32, s.nodes.select { |n| n.key.start_with?("ko") }.sum(&:match_count)
    assert_equal 120, pool_matches + s.nodes.sum(&:match_count)

    # La charge par joueur, elle, ne bouge pas : 4 matchs de tableau chacun.
    assert_equal 4, s.node("ok").round_count
  end

  # ── 24 joueurs : 8 poules de 3 (pas de 4e, donc consolante deux fois plus petite)

  test "8 poules de 3 : consolante de 8 places à partir de la 17e" do
    s = structure(pool_count: 8, players_per_pool: 3)

    ko = s.node("ko")
    assert_equal [17, 24], ko.places
    assert_equal 8, ko.size
    # Seuls les perdants de barrage descendent : il n'y a pas de 4e de poule.
    assert_equal [CriteriumStructure::Losers["barrage", 1]], ko.sources
    assert_equal 8, ko.entrants
  end

  test "8 poules de 3 : la consolante de 8 rejoue ses 4 places basses" do
    s = structure(pool_count: 8, players_per_pool: 3)

    ko_keys = s.nodes.map(&:key).select { |k| k.start_with?("ko") }
    assert_equal %w[ko ko:19-20 ko:21-24 ko:23-24].sort, ko_keys.sort
    # 8/2 × log2(8) = 12 matchs pour disputer les 8 places de la consolante.
    assert_equal 12, s.nodes.select { |n| n.key.start_with?("ko") }.sum(&:match_count)
  end

  test "les 4es de poule n'entrent en consolante qu'en poules de 4" do
    assert_includes structure(pool_count: 8, players_per_pool: 4).node("ko").sources,
                    CriteriumStructure::PoolQualifiers[4]
    assert_not_includes structure(pool_count: 8, players_per_pool: 3).node("ko").sources,
                        CriteriumStructure::PoolQualifiers[4]
  end

  # ── Conservation des effectifs : aucun joueur perdu, aucun en double ─────────

  test "poules de 4 : tout le monde entre en phase finale (4n)" do
    [2, 4, 5, 8, 16].each do |pool_count|
      s = structure(pool_count: pool_count, players_per_pool: 4)

      assert_equal pool_count * 4, s.final_phase_entrants,
                   "#{pool_count} poules de 4 : effectif de phase finale incohérent"
      # n 1ers + n vainqueurs de barrage d'un côté, n 4es + n perdants de l'autre.
      assert_equal pool_count * 2, s.node("ok").entrants
      assert_equal pool_count * 2, s.node("ko").entrants
    end
  end

  test "poules de 3 : tout le monde entre en phase finale (3n)" do
    [2, 4, 5, 8, 16].each do |pool_count|
      s = structure(pool_count: pool_count, players_per_pool: 3)

      assert_equal pool_count * 3, s.final_phase_entrants,
                   "#{pool_count} poules de 3 : effectif de phase finale incohérent"
      assert_equal pool_count * 2, s.node("ok").entrants
      assert_equal pool_count,     s.node("ko").entrants
    end
  end

  test "les barrages sont un nœud de transit : aucune place, les deux camps sortent" do
    barrage = structure(pool_count: 8, players_per_pool: 4).node("barrage")

    assert barrage.transit?
    assert_nil barrage.places
    assert_equal 1, barrage.round_count
    assert_equal [CriteriumStructure::PoolQualifiers[2],
                  CriteriumStructure::PoolQualifiers[3]], barrage.sources
    assert_equal :cross_pool, barrage.pairing
  end

  # ── Mode intégral : un seul tableau, sans barrage ni consolante ──────────────

  test "mode intégral à 16 joueurs : le même arbre que le tableau final standard" do
    integral = structure(pool_count: 4, players_per_pool: 4, mode: :integral)
    standard = structure(pool_count: 8, players_per_pool: 4)

    keys = %w[ok ok:9-16 ok:13-16 ok:15-16 ok:11-12 ok:5-8 ok:7-8 ok:3-4].sort
    assert_equal keys, integral.nodes.map(&:key).sort
    # Le mode ne change QUE l'entrée dans le tableau (pas de barrage, pas de
    # consolante) : l'arbre de classement d'un tableau de 16 est le même partout.
    assert_equal keys, standard.nodes.map(&:key).select { |k| k.start_with?("ok") }.sort
  end

  test "mode intégral à 16 joueurs : les 16 places sont attribuées une seule fois" do
    s = structure(pool_count: 4, players_per_pool: 4, mode: :integral)

    # Règle de lecture uniforme : la finale d'un nœud attribue places.first et
    # places.first + 1. Les 8 finales doivent donc couvrir 1..16 exactement.
    awarded = s.nodes.flat_map { |n| [n.first_place, n.first_place + 1] }

    assert_equal (1..16).to_a, awarded.sort
    assert_equal 16, awarded.uniq.size
  end

  test "mode intégral : ni barrage ni consolante" do
    s = structure(pool_count: 4, players_per_pool: 4, mode: :integral)

    assert_nil s.node("barrage")
    assert_nil s.node("ko")
    assert_equal :pool_rank, s.node("ok").pairing
    assert_equal 16, s.node("ok").entrants
  end

  test "mode intégral : l'effectif réel pilote la taille du tableau" do
    # 11 joueurs en poules de 4/4/3 → tableau unique de 16 (5 byes).
    s = CriteriumStructure.new(pool_count: 3, players_per_pool: 4,
                               mode: :integral, player_count: 11)

    assert_equal 16, s.node("ok").size
    assert_equal 11, s.node("ok").entrants
    assert_equal [1, 16], s.node("ok").places
  end

  # ── Coordonnées en base : pas de collision possible ─────────────────────────

  test "chaque nœud a une clé et un couple phase/branche uniques" do
    [{ pool_count: 8, players_per_pool: 4 },
     { pool_count: 8, players_per_pool: 3 },
     { pool_count: 4, players_per_pool: 4, mode: :integral }].each do |params|
      nodes = structure(**params).nodes

      assert_equal nodes.size, nodes.map(&:key).uniq.size,
                   "clés dupliquées pour #{params}"
      assert_equal nodes.size, nodes.map { |n| [n.phase, n.branch] }.uniq.size,
                   "coordonnées (phase, branche) dupliquées pour #{params}"
    end
  end

  test "les trois tableaux principaux occupent la branche main, les classements leur clé" do
    s = structure(pool_count: 8, players_per_pool: 4)

    assert_equal ["barrage", TournamentRound::MAIN_BRANCH],     coords(s.node("barrage"))
    assert_equal ["bracket", TournamentRound::MAIN_BRANCH],     coords(s.node("ok"))
    assert_equal ["consolation", TournamentRound::MAIN_BRANCH], coords(s.node("ko"))
    assert_equal %w[classification ok:5-8], coords(s.node("ok:5-8"))
    assert_equal %w[classification ko:21-24], coords(s.node("ko:21-24"))
  end

  test "toutes les phases déclarées sont des phases valides de TournamentRound" do
    s = structure(pool_count: 8, players_per_pool: 4)

    s.nodes.each do |node|
      assert_includes TournamentRound::PHASES, node.phase,
                      "phase inconnue « #{node.phase} » pour le nœud #{node.key}"
    end
  end

  # ── Sources : chaque mini-tableau naît des perdants du bon tour ──────────────

  test "chaque mini-tableau reçoit les perdants du tour qui correspond à ses places" do
    s = structure(pool_count: 8, players_per_pool: 4)

    # Tableau OK de 16 : perdants du tour 3 (demies) → 3/4 · tour 2 (quarts) → 5-8
    # · tour 1 (16es) → 9 ex æquo. C'est la formule offset + size / 2**r.
    assert_equal [CriteriumStructure::Losers["ok", 3]], s.node("ok:3-4").sources
    assert_equal [CriteriumStructure::Losers["ok", 2]], s.node("ok:5-8").sources
    assert_equal [CriteriumStructure::Losers["ok", 1]], s.node("ok:9-16").sources
    # Le 7e/8e vient des perdants du 1er tour du 5e-8e, pas du tableau OK.
    assert_equal [CriteriumStructure::Losers["ok:5-8", 1]], s.node("ok:7-8").sources
  end

  test "le tableau final réunit les 1ers de poule et les vainqueurs de barrage" do
    ok = structure(pool_count: 8, players_per_pool: 4).node("ok")

    assert_equal [CriteriumStructure::PoolQualifiers[1],
                  CriteriumStructure::Winners["barrage", 1]], ok.sources
    assert_equal :exempt_first, ok.pairing
  end

  test "un tableau non puissance de deux est arrondi au-dessus (byes)" do
    # 5 poules de 4 → 10 entrants au tableau final → tableau de 16 avec 6 byes.
    s = structure(pool_count: 5, players_per_pool: 4)

    assert_equal 16, s.node("ok").size
    assert_equal 10, s.node("ok").entrants
    # La consolante démarre APRÈS la dernière place du tableau final, même si
    # certaines de ces places resteront vacantes (compaction au Lot 5).
    assert_equal [17, 32], s.node("ko").places
  end

  # ── Libellés ────────────────────────────────────────────────────────────────

  test "les libellés distinguent un match de classement d'un mini-tableau" do
    s = structure(pool_count: 8, players_per_pool: 4)

    assert_equal "Match pour la 3e place", s.node("ok:3-4").label
    assert_equal "Places 5 à 8",           s.node("ok:5-8").label
    assert_equal "Match pour la 7e place", s.node("ok:7-8").label
    assert_equal "Match pour la 19e place", s.node("ko:19-20").label
    assert_equal "Tableau final", s.node("ok").label
    assert_equal "Consolante",    s.node("ko").label
  end

  private

  def structure(**params) = CriteriumStructure.new(**params)

  def coords(node) = [node.phase, node.branch]
end
