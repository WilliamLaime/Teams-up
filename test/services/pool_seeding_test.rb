require "test_helper"

# ── Tests Lot 7 — constitution des poules ─────────────────────────────────────
# Deux modes, deux exigences distinctes :
#
#   • "random" doit reproduire le serpentin historique À L'IDENTIQUE. Ce mode est
#     celui de tous les tournois déjà en base : le sortir de PoolBuilder ne doit
#     rien changer à la répartition.
#   • "pots" doit garantir la propriété du règlement — chaque poule reçoit
#     exactement un joueur de chaque chapeau — sans jamais perdre ni dupliquer un
#     joueur, et sans changer les TAILLES de poules (changer de mode change la
#     composition, pas la structure).
#
# Dans les deux cas, le déterminisme est une assertion à part entière : la
# répartition est rejouée à chaque correction de score, elle doit retomber sur
# elle-même.
class PoolSeedingTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Ping chapeaux", slug: "ping-pong", icon: "🏓")
    @admin = create_test_user(email: "admin-pot-#{SecureRandom.hex(4)}@test.fr")
  end

  def teardown
    teardown_db
  end

  # ── Mode aléatoire ──────────────────────────────────────────────────────────

  test "le mode par défaut reproduit le serpentin historique" do
    tournament = build_tournament(8, format: "poules")
    PoolSeeding.new(tournament).assign!

    # 8 joueurs, 2 poules : le serpentin donne 0-1 puis 1-0, une ligne sur deux.
    assert_equal [0, 1, 1, 0, 0, 1, 1, 0], pools_in_draw_order(tournament)
  end

  test "le serpentin équilibre les poules quand l'effectif ne se divise pas" do
    tournament = build_tournament(11)
    PoolSeeding.new(tournament).assign!

    assert_equal [3, 4, 4], pool_sizes(tournament)
  end

  # ── Mode chapeaux ───────────────────────────────────────────────────────────

  test "chaque poule reçoit exactement un joueur de chaque chapeau" do
    tournament = build_tournament(32, mode: "pots", pots: 2)
    fill_pots!(tournament, 2)

    PoolSeeding.new(tournament).assign!

    assert_equal 8, tournament.reload.pools.size
    tournament.pools.each do |index, members|
      assert_equal 4, members.size, "la poule #{index} n'a pas 4 joueurs"
      assert_equal 1, members.count { |tu| tu.pot == 1 }, "poule #{index} : pas 1 joueur du chapeau 1"
      assert_equal 1, members.count { |tu| tu.pot == 2 }, "poule #{index} : pas 1 joueur du chapeau 2"
      assert_equal 2, members.count { |tu| tu.pot.nil? }, "poule #{index} : pas 2 joueurs du chapeau général"
    end
  end

  test "les chapeaux ne perdent ni ne dupliquent aucun joueur" do
    tournament = build_tournament(32, mode: "pots", pots: 2)
    fill_pots!(tournament, 2)

    PoolSeeding.new(tournament).assign!

    placed = tournament.reload.pools.values.flatten
    assert_equal 32, placed.size
    assert_equal 32, placed.map(&:id).uniq.size
  end

  test "un chapeau plus grand que le nombre de poules ne perd personne" do
    # 12 joueurs → 4 poules de 3, mais 6 joueurs cochés « chapeau 1 » : deux d'entre
    # eux ne peuvent pas être têtes de poule. Le règlement ne dit rien de ce cas —
    # l'important est qu'ils retombent dans le chapeau général, pas hors du tournoi.
    tournament = build_tournament(12, mode: "pots", pots: 1)
    ordered(tournament).first(6).each { |tu| tu.update!(pot: 1) }

    PoolSeeding.new(tournament).assign!

    placed = tournament.reload.pools.values.flatten
    assert_equal 12, placed.size
    assert_equal 12, placed.map(&:id).uniq.size
    assert_equal [3, 3, 3, 3], pool_sizes(tournament)
    # Chaque poule garde SA tête de série ; le surplus s'ajoute par-dessus, il ne
    # prend la place de personne.
    assert tournament.pools.values.all? { |m| m.count { |tu| tu.pot == 1 } >= 1 },
           "une poule s'est retrouvée sans joueur du chapeau 1"
  end

  test "le mode chapeaux respecte les tailles de poules du plan" do
    # 11 joueurs en Critérium → plan [4, 4, 3] : changer de mode de constitution
    # ne doit pas changer la structure du tournoi, seulement sa composition.
    tournament = build_tournament(11, mode: "pots", pots: 2)
    fill_pots!(tournament, 2)

    PoolSeeding.new(tournament).assign!

    assert_equal [3, 4, 4], pool_sizes(tournament)
  end

  test "aucun chapeau rempli : le mode chapeaux répartit quand même tout le monde" do
    tournament = build_tournament(16, mode: "pots", pots: 2)

    PoolSeeding.new(tournament).assign!

    assert_equal [4, 4, 4, 4], pool_sizes(tournament)
  end

  test "un chapeau au-delà du nombre déclaré retombe dans le chapeau général" do
    # L'organisateur avait 3 chapeaux, il redescend à 2 : le select du panneau
    # n'affiche plus « chapeau 3 ». Le moteur doit lire la même chose que l'écran.
    # 11 joueurs → poules [4, 4, 3] : des tailles inégales, seul cas où « un par
    # poule » et « au remplissage » ne donnent pas par hasard le même résultat.
    tournament = build_tournament(11, mode: "pots", pots: 1)
    fill_pots!(tournament, 1)
    ordered(tournament).slice(3, 3).each { |tu| tu.update!(pot: 2) }

    PoolSeeding.new(tournament).assign!

    assert_equal [3, 4, 4], pool_sizes(tournament)
    # Le chapeau 1, déclaré, garde sa règle : un joueur par poule.
    assert_equal [1, 1, 1], tournament.pools.values.map { |m| m.count { |tu| tu.pot == 1 } }
    # Le chapeau 2, non déclaré, suit le remplissage — donc pas un par poule.
    counts = tournament.pools.values.map { |m| m.count { |tu| tu.pot == 2 } }
    assert_equal 3, counts.sum, "un joueur du chapeau 2 s'est perdu"
    assert_not_equal [1, 1, 1], counts, "le chapeau 2 a été traité comme un vrai chapeau"
  end

  # ── Déterminisme ────────────────────────────────────────────────────────────

  test "deux répartitions successives donnent le même résultat" do
    %w[random pots].each do |mode|
      tournament = build_tournament(16, mode: mode, pots: 2)
      fill_pots!(tournament, 2)

      PoolSeeding.new(tournament).assign!
      first = pools_in_draw_order(tournament)
      PoolSeeding.new(tournament).assign!

      assert_equal first, pools_in_draw_order(tournament), "mode #{mode} non déterministe"
    end
  end

  test "un co-organisateur qui joue est réparti comme n'importe quel joueur" do
    tournament = build_tournament(8, mode: "pots", pots: 2)
    # Le drapeau de gestion est indépendant du rôle : cette inscription occupe une
    # place ET donne les droits. PoolSeeding ne doit pas la traiter à part.
    co_org = ordered(tournament).first
    co_org.update!(co_organizer: true)
    fill_pots!(tournament, 2)

    PoolSeeding.new(tournament).assign!

    assert tournament.organizer?(co_org.user), "le drapeau doit donner les droits de gestion"
    assert_not_nil co_org.reload.pool, "un co-organisateur joueur doit être tiré dans une poule"
    assert_equal 8, tournament.tournament_users.players.approved.where.not(pool: nil).count
  end

  private

  def build_tournament(count, format: "criterium_federal", mode: nil, pots: nil)
    tournament = Tournament.create!(name: "T#{SecureRandom.hex(3)}", sport: @sport, user: @admin,
                                    format: format, status: "open", max_players: count,
                                    pool_seeding_mode: mode, seeded_pot_count: pots,
                                    date: Date.tomorrow, place: "Salle test")
    count.times do |i|
      user = create_test_user(email: "ps#{i}-#{SecureRandom.hex(3)}@test.fr")
      tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    # Le tirage au sort figé au lancement : la seule source d'aléa des moteurs.
    ordered(tournament).each_with_index { |tu, index| tu.update_column(:draw_order, index) }
    tournament
  end

  def ordered(tournament) = tournament.tournament_users.players.approved.order(:id).to_a

  # Un joueur par poule et par chapeau : les `pool_count` premiers du tirage au
  # chapeau 1, les suivants au chapeau 2, etc.
  def fill_pots!(tournament, pot_count)
    per_pot = tournament.pool_count
    players = tournament.tournament_users.players.approved.order(:draw_order, :id).to_a

    pot_count.times do |index|
      players.slice(index * per_pot, per_pot).to_a.each { |tu| tu.update!(pot: index + 1) }
    end
  end

  # La poule de chaque joueur, dans l'ordre du tirage — la signature complète
  # d'une répartition, comparable d'un appel à l'autre.
  def pools_in_draw_order(tournament)
    tournament.tournament_users.players.approved.order(:draw_order, :id).pluck(:pool)
  end

  def pool_sizes(tournament) = tournament.reload.pools.values.map(&:size).sort
end
