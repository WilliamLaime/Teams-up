require "test_helper"

# Tests du classement de poule au règlement FFTT (Critérium Fédéral) :
# points-parties 2 V / 1 D, puis départage RESTREINT au sous-groupe d'ex-æquo
# (confrontation directe → quotient de manches → quotient de points → tirage au sort).
#
# Chaque scénario est construit pour qu'UN SEUL critère puisse trancher, et pour que
# les critères de rang inférieur donneraient volontairement l'ordre INVERSE — sinon
# le test passerait même si le critère testé n'était jamais appliqué.
class PoolStandingsTest < ActiveSupport::TestCase
  def setup
    # Slug exact "ping-pong" : c'est lui qui déclenche le barème 2/1 et les règles
    # de score 11 points / 2 d'écart (cf. Sport#pool_points_rules et #scoring_rules).
    @sport = Sport.create!(name: "Ping-Pong test", slug: "ping-pong", icon: "🏓")
    @admin = create_test_user(email: "admin-#{SecureRandom.hex(4)}@test.fr")
    @tournament = Tournament.create!(name: "T#{SecureRandom.hex(3)}", sport: @sport, user: @admin,
                                    format: "poules", status: "in_progress", max_players: 8,
                                    date: Date.tomorrow, place: "Terrain test")
    @round = @tournament.tournament_rounds.create!(phase: "pool", number: 1, status: "in_progress")
    @position = 0
  end

  def teardown
    teardown_db
  end

  # Crée `count` joueurs avec un draw_order croissant (0, 1, 2…) — c'est le tirage
  # au sort figé, dernier critère de départage.
  def players(count)
    count.times.map do |i|
      user = create_test_user(email: "p#{i}-#{SecureRandom.hex(3)}@test.fr")
      @tournament.tournament_users.create!(user: user, role: "joueur", status: "approved",
                                          draw_order: i, pool: 0)
    end
  end

  # Pose un match de poule joué : `sets` vu du côté de `winner`.
  # Ex. beat!(a, b, [[11, 0], [11, 0], [11, 0]]) → a gagne 3-0 en écrasant b.
  def beat!(winner, loser, sets)
    match = @round.tournament_matches.create!(player_a: winner, player_b: loser,
                                             position: (@position += 1))
    match.assign_score(sets)
    match.save!
    assert_equal winner.id, match.reload.winner_id, "score invalide : le vainqueur attendu n'est pas dérivé"
    match
  end

  SWEEP  = [[11, 0], [11, 0], [11, 0]].freeze  # 3-0 écrasant
  NARROW = [[11, 9], [11, 9], [11, 9]].freeze  # 3-0 serré

  def standings(members) = PoolStandings.new(@tournament, members)

  # ── Barème points-parties ───────────────────────────────────────────────────

  test "barème FFTT : 2 points par victoire, 1 par défaite jouée" do
    a, b, c = players(3)
    beat!(a, b, SWEEP)
    beat!(a, c, SWEEP)
    beat!(b, c, SWEEP)

    rows = standings([a, b, c]).rows.index_by { |row| row.player.id }

    assert_equal 4, rows[a.id].points, "2 victoires = 4 points"
    assert_equal 3, rows[b.id].points, "1 victoire + 1 défaite = 2 + 1 = 3 points"
    assert_equal 2, rows[c.id].points, "2 défaites = 2 points"
    assert_equal [a.id, b.id, c.id], standings([a, b, c]).ordered.map(&:id)
  end

  test "barème FFTT : un forfait ne rapporte aucun point (contre 1 pour une défaite jouée)" do
    a, b, c = players(3)
    beat!(a, b, SWEEP)
    beat!(a, c, SWEEP)
    # c déclare forfait contre b : b gagne d'office, c ne marque pas le point de défaite.
    @round.tournament_matches.create!(player_a: b, player_b: c, position: (@position += 1),
                                     forfeit: true, retired_player: c)

    rows = standings([a, b, c]).rows.index_by { |row| row.player.id }

    assert_equal 3, rows[b.id].points, "1 victoire (par forfait) + 1 défaite jouée = 3"
    assert_equal 1, rows[c.id].points, "1 défaite jouée (1) + 1 forfait (0) = 1"
  end

  test "les byes ne rapportent aucun point" do
    a, b, c = players(3)
    beat!(a, b, SWEEP)
    beat!(a, c, SWEEP)
    beat!(b, c, SWEEP)
    before = standings([a, b, c]).rows.index_by { |row| row.player.id }[c.id].points

    # Poule de 3 : le calendrier round-robin donne un bye par joueur. Le compter
    # comme une victoire offrirait 2 points-parties gratuits à tout le monde.
    @round.tournament_matches.create!(player_a: c, is_bye: true, position: (@position += 1))

    after = standings([a, b, c]).rows.index_by { |row| row.player.id }[c.id].points
    assert_equal before, after, "un bye n'est pas une victoire dans une poule"
  end

  # ── (a) Confrontation directe ───────────────────────────────────────────────

  test "départage (a) : à égalité de points, la confrontation directe tranche" do
    a, b, c, d = players(4)
    # a et b finissent à 5 points ; b a battu a. Les scores de a sont volontairement
    # écrasants et ceux de b serrés : si un quotient primait, a passerait devant.
    beat!(b, a, NARROW)
    beat!(a, c, SWEEP)
    beat!(a, d, SWEEP)
    beat!(b, c, NARROW)
    beat!(d, b, NARROW)
    beat!(c, d, NARROW)

    order = standings([a, b, c, d]).ordered

    rows = standings([a, b, c, d]).rows.index_by { |row| row.player.id }
    assert_equal 5, rows[a.id].points
    assert_equal 5, rows[b.id].points
    assert_equal [b.id, a.id], order.first(2).map(&:id),
                 "b a battu a en confrontation directe, il passe devant malgré un moins bon quotient"
    # c et d sont à 4 points ; c a battu d.
    assert_equal [c.id, d.id], order.last(2).map(&:id)
  end

  test "départage (a) : trois ex-æquo entièrement séparés par leur mini-classement" do
    # Il faut 5 joueurs : dans une poule de 4 avec un joueur dominant, trois ex-æquo
    # au mini-classement hiérarchique est impossible — leurs points totaux
    # différeraient exactement de leur mini-classement. Ici les victoires hors
    # sous-groupe compensent (b en gagne 0, c 1, d 2).
    a, b, c, d, e = players(5)
    beat!(a, b, SWEEP)
    beat!(a, c, SWEEP)
    beat!(a, e, SWEEP)
    beat!(d, a, SWEEP)
    beat!(b, c, NARROW)
    beat!(b, d, NARROW)
    beat!(e, b, SWEEP)
    beat!(c, d, NARROW)
    beat!(c, e, SWEEP)
    beat!(d, e, SWEEP)

    standing = standings([a, b, c, d, e])
    rows = standing.rows.index_by { |row| row.player.id }

    assert_equal [6, 6, 6], [rows[b.id].points, rows[c.id].points, rows[d.id].points],
                 "b, c et d sont à 2 V - 2 D, donc 6 points chacun"
    # Le mini-classement b > c > d est hiérarchique (b bat c et d, c bat d) alors que
    # les deux critères suivants pointent dans l'autre sens : quotient de manches
    # identique (tous en 3-0), quotient de POINTS décroissant d > c > b.
    assert_equal [1.0, 1.0, 1.0],
                 [b, c, d].map { |p| rows[p.id].sets_won.fdiv(rows[p.id].sets_lost) },
                 "le quotient de manches ne peut pas départager"
    quotients = [b, c, d].map { |p| rows[p.id].points_won.fdiv(rows[p.id].points_lost) }
    assert quotients[0] < quotients[1] && quotients[1] < quotients[2],
           "le quotient de points donnerait l'ordre INVERSE (d, c, b)"

    assert_equal [a.id, b.id, c.id, d.id, e.id], standing.ordered.map(&:id),
                 "la confrontation directe prime sur les quotients"
  end

  # ── (b) Quotient de manches ─────────────────────────────────────────────────

  test "départage (b) : confrontation directe non concluante (cycle) → quotient de manches" do
    a, b, c = players(3)
    # Cycle parfait : chacun 1 V - 1 D, donc 3 points et un mini-classement à
    # égalité totale. Le quotient de manches doit alors décider.
    beat!(a, b, SWEEP)              # a : 3 manches gagnées, 0 concédée
    beat!(b, c, SWEEP)
    beat!(c, a, [[11, 9], [9, 11], [11, 9], [9, 11], [11, 9]]) # c gagne 3-2

    standing = standings([a, b, c])
    rows = standing.rows.index_by { |row| row.player.id }
    assert_equal [3, 3, 3], [rows[a.id].points, rows[b.id].points, rows[c.id].points],
                 "cycle → tout le monde à 3 points"

    # a : 5 gagnées / 3 concédées = 1.67 · b : 3/3 = 1.0 · c : 3/5 = 0.6
    assert_equal [5, 3], [rows[a.id].sets_won, rows[a.id].sets_lost]
    assert_equal [3, 3], [rows[b.id].sets_won, rows[b.id].sets_lost]
    assert_equal [3, 5], [rows[c.id].sets_won, rows[c.id].sets_lost]
    assert_equal [a.id, b.id, c.id], standing.ordered.map(&:id)
  end

  # ── (c) Quotient de points ──────────────────────────────────────────────────

  test "départage (c) : quotients de manches identiques → quotient de points" do
    a, b, c = players(3)
    # Cycle en 3-0 : quotient de manches = 3/3 = 1.0 pour les trois. Seuls les
    # points marqués peuvent départager.
    beat!(a, b, SWEEP)   # a : +33 / -0
    beat!(b, c, SWEEP)   # b : +33 / -0
    beat!(c, a, NARROW)  # c : +33 / -27  ·  a : +27 / -33

    standing = standings([a, b, c])
    rows = standing.rows.index_by { |row| row.player.id }
    assert_equal [1.0, 1.0, 1.0],
                 [a, b, c].map { |p| rows[p.id].sets_won.fdiv(rows[p.id].sets_lost) },
                 "les trois ont le même quotient de manches"

    # a : 60/33 = 1.82 · b : 33/33 = 1.0 · c : 33/60 = 0.55
    assert_equal [60, 33], [rows[a.id].points_won, rows[a.id].points_lost]
    assert_equal [33, 33], [rows[b.id].points_won, rows[b.id].points_lost]
    assert_equal [33, 60], [rows[c.id].points_won, rows[c.id].points_lost]
    assert_equal [a.id, b.id, c.id], standing.ordered.map(&:id)
  end

  # ── (d) Tirage au sort ──────────────────────────────────────────────────────

  test "départage (d) : égalité totale → draw_order, et le résultat est reproductible" do
    a, b, c = players(3)
    # Cycle en 3-0 avec des scores strictement identiques : aucun critère ne peut
    # séparer les trois joueurs.
    beat!(a, b, SWEEP)
    beat!(b, c, SWEEP)
    beat!(c, a, SWEEP)

    first  = PoolStandings.new(@tournament, [a, b, c]).ordered.map(&:id)
    # Ordre d'entrée délibérément différent : le classement ne doit pas en dépendre.
    second = PoolStandings.new(@tournament, [c, b, a]).ordered.map(&:id)

    assert_equal [a.id, b.id, c.id], first, "draw_order 0, 1, 2 décide"
    assert_equal first, second,
                 "déterminisme : indispensable pour qu'une correction de score rebâtisse le même classement"
  end

  # ── Quotients : cas limites ─────────────────────────────────────────────────

  test "quotient : aucune manche concédée = avantage maximal, 0/0 = neutre" do
    standing = PoolStandings.new(@tournament, [])

    assert_equal Float::INFINITY, standing.send(:quotient, 6, 0), "6 gagnées, 0 concédée"
    assert_equal 0.0, standing.send(:quotient, 0, 0), "aucun match joué → neutre, pas d'erreur"
    assert_in_delta 1.5, standing.send(:quotient, 3, 2), 0.001
  end

  # ── Divers ──────────────────────────────────────────────────────────────────

  test "complete? : vrai seulement quand tous les membres se sont rencontrés" do
    a, b, c = players(3)
    beat!(a, b, SWEEP)
    refute standings([a, b, c]).complete?

    beat!(a, c, SWEEP)
    beat!(b, c, SWEEP)
    assert standings([a, b, c]).complete?
  end

  test "qualifier / place_of : désignent le 1er, 2e, 3e de poule" do
    a, b, c = players(3)
    beat!(a, b, SWEEP)
    beat!(a, c, SWEEP)
    beat!(b, c, SWEEP)

    standing = standings([a, b, c])
    assert_equal a.id, standing.qualifier(1).id
    assert_equal b.id, standing.qualifier(2).id
    assert_equal c.id, standing.qualifier(3).id
    assert_nil standing.qualifier(4), "une poule de 3 n'a pas de 4e"
    assert_equal 2, standing.place_of(b)
  end

  test "les matchs d'une AUTRE poule sont ignorés" do
    a, b, c, d = players(4)
    [c, d].each { |tu| tu.update!(pool: 1) }
    beat!(a, b, SWEEP)
    beat!(c, d, SWEEP) # poule 1 — ne doit pas polluer le classement de la poule 0

    rows = standings([a, b]).rows
    assert_equal [1, 1], rows.map(&:played), "un seul match par joueur dans la poule 0"
  end

  # ── Non-régression : la ronde suisse ne doit pas bouger ─────────────────────

  test "non-régression : le barème 2/1 ne fuit pas dans ranking_points ni rank_key" do
    a, = players(1)
    a.update!(wins: 1, losses: 2)

    assert_nil @sport.ranking_points_rules,
               "le ping-pong ne doit pas acquérir de barème de classement global"
    assert_equal 1, a.ranking_points,
                 "ranking_points reste à 1 pt/victoire (lu par rank_key, donc par la ronde suisse)"
    # Sans ce comportement, un 1 V - 0 D (2 pts) égalerait un 0 V - 2 D (2 pts).
    assert_equal({ win: 2, draw: 0, loss: 1, forfeit: 0 }, @sport.pool_points_rules)
  end

  test "les autres sports gardent leur barème de classement comme barème de poule" do
    # #pool_points_rules ne lit que le slug : pas besoin de persister ces sports
    # (et pas de conflit d'unicité avec les sports déjà seedés).
    assert_equal({ win: 3, draw: 1, loss: 0, forfeit: 0 },
                 Sport.new(slug: "football").pool_points_rules, "barème FIFA conservé")
    assert_equal({ win: 1, draw: 0, loss: 0, forfeit: 0 },
                 Sport.new(slug: "tennis").pool_points_rules,
                 "sport sans barème dédié → 1 pt par victoire, comme aujourd'hui")
  end
end
