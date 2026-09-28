require "test_helper"

# ── Tests CriteriumFlow — barrages + tableau final (Lot 4) ────────────────────
# La consolante et les matchs de classement arrivent au Lot 5 : ici on vérifie que
# les poules débouchent bien sur des barrages CROISÉS, puis sur un tableau final où
# les 1ers de poule sont protégés — et que tout cela est idempotent.
class CriteriumFlowTest < ActiveSupport::TestCase
  def setup
    # Le Critérium est réservé au tennis de table : le slug pilote le barème
    # points-parties 2/1 (Sport#pool_points_rules) et le best_of 5 → 7 en phase
    # finale (Sport#scoring_rules).
    @sport = Sport.create!(name: "Ping test", slug: "ping-pong", icon: "🏓")
    @admin = create_test_user(email: "admin-#{SecureRandom.hex(4)}@test.fr")
  end

  def teardown
    teardown_db
  end

  # `final_phase_mode: "standard"` est EXPLICITE : depuis le Lot 6, les seuils
  # d'effectif du règlement basculent un tournoi de 16 joueurs ou moins en
  # classement intégral (tableau unique, sans barrage ni consolante). Ce fichier
  # teste la variante standard, il doit donc la demander — sinon il testerait, sans
  # le dire, une structure entièrement différente.
  def build_tournament(count, players_per_pool: 4, final_phase_mode: "standard")
    tournament = Tournament.create!(name: "T#{SecureRandom.hex(3)}", sport: @sport, user: @admin,
                                    format: "criterium_federal", status: "open", max_players: count,
                                    players_per_pool: players_per_pool,
                                    final_phase_mode: final_phase_mode,
                                    date: Date.tomorrow, place: "Salle test")
    count.times do |i|
      user = create_test_user(email: "p#{i}-#{SecureRandom.hex(3)}@test.fr")
      tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    # Le tirage au sort que TournamentsController#start effectue au lancement.
    # Indispensable : `draw_order` est la seule source d'aléa des moteurs, et c'est
    # lui qui rend le calendrier des poules et les appariements reproductibles.
    tournament.tournament_users.players.approved.order(:id).each_with_index do |tu, index|
      tu.update_column(:draw_order, index)
    end
    tournament
  end

  # Classement des poules relu depuis la base. Tournament#pool_standings est
  # memoïsé par instance : on repart d'une instance neuve pour être sûr de voir
  # l'état d'après les derniers scores saisis.
  def standings_of(tournament) = Tournament.find(tournament.id).pool_standings

  # Résout TOUS les matchs en attente, toutes rondes confondues. On ne peut pas se
  # reposer sur Tournament#current_round : le Critérium fait tourner plusieurs
  # branches en parallèle et les barrages n'y figurent pas.
  def resolve_all_pending!(tournament, &winner_picker)
    picker = winner_picker || ->(match) { match.player_a }
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: tournament.id })
                   .where(status: "pending", is_bye: false)
                   .to_a
                   .each { |match| win_tournament_match!(match, picker.call(match)) }
  end

  # Joue les poules jusqu'à ce que les barrages apparaissent.
  def play_pools!(tournament, &winner_picker)
    TournamentEngine.for(tournament).next_round!
    20.times do
      break if tournament.barrage_rounds.exists?

      resolve_all_pending!(tournament, &winner_picker)
      TournamentEngine.for(tournament).next_round!
    end
    tournament.reload
  end

  def advance!(tournament) = TournamentEngine.for(tournament).next_round!

  # ── Barrages ────────────────────────────────────────────────────────────────

  test "les poules terminées débouchent sur un tour de barrages" do
    tournament = build_tournament(16)
    play_pools!(tournament)

    assert_equal 1, tournament.barrage_rounds.count
    round = tournament.barrage_rounds.first
    assert_equal "barrage", round.phase
    assert_equal TournamentRound::MAIN_BRANCH, round.branch
    # 4 poules → 4 deuxièmes contre 4 troisièmes → 4 barrages.
    assert_equal 4, round.tournament_matches.count
  end

  test "aucun barrage n'oppose deux joueurs de la même poule" do
    # 2, 3, 4 et 8 poules : le croisement doit tenir à toutes les tailles.
    [8, 12, 16, 32].each do |count|
      tournament = build_tournament(count)
      play_pools!(tournament)

      tournament.barrage_rounds.first.tournament_matches.reject(&:is_bye).each do |match|
        assert_not_equal match.player_a.pool, match.player_b.pool,
                         "#{count} joueurs : un barrage oppose deux joueurs de la poule " \
                         "#{match.player_a.pool}"
      end
    end
  end

  test "les barrages réunissent exactement les 2es et les 3es de poule" do
    tournament = build_tournament(16)
    play_pools!(tournament)

    entrants = tournament.barrage_rounds.first.tournament_matches.flat_map(&:players)
    positions = entrants.map { |tu| tournament.pool_position_of(tu) }.sort

    assert_equal [2, 2, 2, 2, 3, 3, 3, 3], positions,
                 "seuls les 2es et 3es de poule jouent les barrages"
  end

  # Un 2e de poule qui a ABANDONNÉ le tournoi est écarté des barrages (cf.
  # CriteriumFlow#qualifiers_at) : il y a alors un 2e de moins que de 3es. L'ancien
  # alignement `seconds.zip(thirds)` coupait la liste des 3es à la longueur de celle
  # des 2es — le dernier 3e, le PLUS FORT, disparaissait du tournoi sans bruit.
  test "un 2e parti ne fait disparaître aucun 3e : le plus fort prend le bye" do
    tournament = build_tournament(16)
    players = tournament.tournament_users.players.approved.order(:draw_order).to_a
    players.each_with_index { |tu, i| tu.update_column(:pool, i % 4) }
    # 2es des poules 0, 1, 2 (celui de la poule 3 est parti) ; 3es des 4 poules,
    # par force croissante, comme les fournit #barrage_pairs.
    seconds = players.first(3)
    thirds  = players.last(4)

    pairs = CriteriumFlow.new(tournament).send(:avoid_same_pool, seconds, thirds)

    assert_equal 4, pairs.size, "un barrage (ou bye) par 3e"
    assert_equal thirds.map(&:id).sort, pairs.map(&:last).compact.map(&:id).sort,
                 "chaque 3e a sa place"
    assert_equal [nil, thirds.last], pairs.find { |second, _| second.nil? },
                 "le 3e le plus fort prend le bye du 2e manquant"
    assert(pairs.none? { |a, b| a && b && a.pool == b.pool }, "aucun barrage intra-poule")
  end

  test "les 1ers de poule ne jouent pas les barrages" do
    tournament = build_tournament(16)
    play_pools!(tournament)

    barrage_ids = tournament.barrage_rounds.first.tournament_matches.flat_map(&:players).map(&:id)
    firsts = standings_of(tournament).values.map { |pool| pool.qualifier(1) }

    assert_equal 4, firsts.size
    firsts.each do |first|
      assert_not_includes barrage_ids, first.id, "un 1er de poule est exempté de barrage"
    end
  end

  test "un barrage se joue au meilleur des 7 manches, comme l'exige le règlement" do
    tournament = build_tournament(16)
    play_pools!(tournament)

    barrage = tournament.barrage_rounds.first.tournament_matches.reject(&:is_bye).first
    pool    = tournament.pool_rounds.first.tournament_matches.reject(&:is_bye).first

    assert_equal 4, barrage.sets_to_win, "phase finale → 4 manches gagnantes"
    assert_equal 3, pool.sets_to_win,    "poule → 3 manches gagnantes"
  end

  # ── Tableau final ───────────────────────────────────────────────────────────

  test "les barrages terminés déclenchent le tableau final" do
    tournament = build_tournament(16)
    play_pools!(tournament)
    resolve_all_pending!(tournament)
    advance!(tournament)

    assert tournament.reload.bracket_started?
    first_round = tournament.bracket_rounds.first
    # 4 1ers de poule + 4 vainqueurs de barrage → tableau de 8 → 4 matchs.
    assert_equal 8, tournament.final_size
    assert_equal 4, first_round.tournament_matches.count
  end

  test "le tableau final réunit les 1ers de poule et les vainqueurs de barrage" do
    tournament = build_tournament(16)
    play_pools!(tournament)
    winners = tournament.barrage_rounds.first.tournament_matches.map { |m| m.player_a }
    resolve_all_pending!(tournament)
    advance!(tournament)

    entrants = tournament.bracket_rounds.first.tournament_matches.flat_map(&:players)
    firsts   = standings_of(tournament).values.map { |pool| pool.qualifier(1) }

    assert_equal 8, entrants.size
    assert_equal (firsts + winners).map(&:id).sort, entrants.map(&:id).sort
  end

  test "ordre protégé : aucun 1er de poule n'en rencontre un autre au premier tour" do
    [16, 32].each do |count|
      tournament = build_tournament(count)
      play_pools!(tournament)
      resolve_all_pending!(tournament)
      advance!(tournament)

      first_ids = standings_of(tournament).values.map { |pool| pool.qualifier(1).id }.to_set

      tournament.bracket_rounds.first.tournament_matches.reject(&:is_bye).each do |match|
        both_firsts = match.players.count { |tu| first_ids.include?(tu.id) }
        assert_operator both_firsts, :<=, 1,
                        "#{count} joueurs : deux 1ers de poule s'affrontent au 1er tour"
      end
    end
  end

  test "un vainqueur de barrage ne retombe pas sur le 1er de sa propre poule" do
    tournament = build_tournament(32)
    play_pools!(tournament)
    resolve_all_pending!(tournament)
    advance!(tournament)

    first_ids = standings_of(tournament).values.map { |pool| pool.qualifier(1).id }.to_set

    tournament.bracket_rounds.first.tournament_matches.reject(&:is_bye).each do |match|
      first = match.players.find { |tu| first_ids.include?(tu.id) }
      promoted = match.players.find { |tu| !first_ids.include?(tu.id) }
      next if first.nil? || promoted.nil?

      assert_not_equal first.pool, promoted.pool,
                       "un vainqueur de barrage affronte le 1er de sa poule"
    end
  end

  test "les entrants du tableau final sont marqués qualifiés, les autres restent actifs" do
    tournament = build_tournament(16)
    play_pools!(tournament)
    resolve_all_pending!(tournament)
    advance!(tournament)

    assert_equal 8, tournament.tournament_users.qualified.count
    # Les perdants de barrage NE SONT PAS éliminés : ils descendent en consolante
    # (Lot 5). Aucun joueur ne doit être marqué "eliminated" à ce stade.
    assert_equal 0, tournament.tournament_users.players.where(state: "eliminated").count
  end

  # Une correction de score peut sortir du tableau final un joueur qui y était :
  # l'ancien code le qualifiait à l'ouverture du tableau et ne le « dé-qualifiait »
  # jamais — il gardait l'icône « Qualifié » alors qu'il jouait la consolante.
  test "après une reconstruction de la phase finale, seuls les entrants réels restent qualifiés" do
    tournament = build_tournament(16)
    play_pools!(tournament)
    resolve_all_pending!(tournament)
    advance!(tournament)
    assert_equal 8, tournament.tournament_users.qualified.count

    # Simule un joueur qualifié à tort par un ancien état : un 4e de poule, qui
    # n'entre jamais au tableau final.
    fourth = standings_of(tournament).values.first.qualifier(4)
    fourth.update!(state: "qualified")
    # Même chose que TournamentMatchesController après une correction en poule.
    tournament.tournament_rounds.final_phase.destroy_all
    play_pools!(tournament)
    resolve_all_pending!(tournament)
    advance!(tournament)

    assert_equal "active", fourth.reload.state
    assert_equal 8, tournament.tournament_users.qualified.count
  end

  test "tant que le tableau final n'existe plus, personne n'est qualifié" do
    tournament = build_tournament(16)
    play_pools!(tournament)
    resolve_all_pending!(tournament)
    advance!(tournament)

    tournament.tournament_rounds.final_phase.destroy_all
    advance!(tournament) # recrée les barrages, pas encore le tableau

    assert_equal 0, tournament.tournament_users.qualified.count
  end

  test "bracket_rounds ne contient que le tableau final, jamais les barrages" do
    tournament = build_tournament(16)
    play_pools!(tournament)
    resolve_all_pending!(tournament)
    advance!(tournament)

    phases = tournament.bracket_rounds.map(&:phase).uniq
    assert_equal ["bracket"], phases
    assert_equal 1, tournament.barrage_rounds.count
  end

  # ── Idempotence ─────────────────────────────────────────────────────────────

  test "advance! appelé trois fois de suite ne crée qu'un seul tour de barrages" do
    tournament = build_tournament(16)
    play_pools!(tournament)

    before = TournamentRound.where(tournament_id: tournament.id).count
    3.times { advance!(tournament) }

    assert_equal 1, tournament.barrage_rounds.count
    assert_equal before, TournamentRound.where(tournament_id: tournament.id).count,
                 "un appel sur un tour non terminé ne doit rien créer"
  end

  test "advance! appelé trois fois après les barrages ne crée qu'un tour de tableau" do
    tournament = build_tournament(16)
    play_pools!(tournament)
    resolve_all_pending!(tournament)

    3.times { advance!(tournament) }

    assert_equal 1, tournament.bracket_rounds.count
    assert_equal 4, tournament.bracket_rounds.first.tournament_matches.count
  end

  test "les matchs ne sont jamais dupliqués sur un enchaînement complet" do
    tournament = build_tournament(16)
    play_pools!(tournament)

    12.times do
      advance!(tournament)
      resolve_all_pending!(tournament)
      advance!(tournament)
    end

    tournament.tournament_rounds.each do |round|
      pairs = round.tournament_matches.reject(&:is_bye).map { |m| [m.player_a_id, m.player_b_id].sort }
      assert_equal pairs.uniq.size, pairs.size,
                   "doublon de match dans #{round.phase}/#{round.branch} n°#{round.number}"
    end
  end

  # ── Déroulé jusqu'au bout du tableau final ──────────────────────────────────

  test "le tableau final va jusqu'à sa finale" do
    tournament = build_tournament(16)
    play_pools!(tournament)

    20.times do
      resolve_all_pending!(tournament)
      advance!(tournament)
      break if tournament.reload.bracket_rounds.count >= 3 &&
               tournament.bracket_rounds.last.complete?
    end

    # Tableau de 8 → quarts, demies, finale.
    assert_equal 3, tournament.bracket_rounds.count
    assert_equal 1, tournament.bracket_rounds.last.tournament_matches.count
  end

  test "le tournoi n'est pas déclaré terminé avant que tous les tableaux le soient" do
    tournament = build_tournament(16)
    play_pools!(tournament)
    resolve_all_pending!(tournament)
    advance!(tournament)

    # Le tableau final vient de démarrer : rien n'est joué.
    assert_not tournament.reload.completed?
  end

  # ── Poules de 3 ─────────────────────────────────────────────────────────────

  test "poules de 3 : 12 joueurs → 4 poules, 4 barrages, tableau de 8" do
    tournament = build_tournament(12, players_per_pool: 3)
    play_pools!(tournament)

    assert_equal 4, tournament.pools.size
    assert_equal [3, 3, 3, 3], tournament.pools.values.map(&:size)
    assert_equal 4, tournament.barrage_rounds.first.tournament_matches.count

    resolve_all_pending!(tournament)
    advance!(tournament)

    assert_equal 4, tournament.bracket_rounds.first.tournament_matches.count
  end

  test "en poules de 3, les byes de calendrier ne rapportent aucun point-partie" do
    tournament = build_tournament(12, players_per_pool: 3)
    play_pools!(tournament)

    # Une poule de 3 se joue en 2 matchs par joueur : le vainqueur des deux compte
    # 4 points-parties (2 × victoire), jamais 6 — le bye du calendrier round-robin
    # ne doit rien rapporter.
    rows = standings_of(tournament).values.first.rows
    assert_equal 2, rows.first.played
    assert_equal 4, rows.first.points
    assert_operator rows.sum(&:points), :<=, 3 * 4
  end

  # ── Non-régression sur le format « Poules » ─────────────────────────────────

  test "un tournoi Poules classique ne passe jamais par CriteriumFlow" do
    tournament = build_tournament(16)
    tournament.update!(format: "poules")
    play_pools!(tournament) # ne créera aucun barrage

    assert_equal 0, tournament.barrage_rounds.count
    assert tournament.bracket_started?, "le format Poules bascule directement en tableau final"
  end

  # ── Seeding inter-poules : au ratio, pas au total ───────────────────────────

  # Un effectif impair produit des poules de tailles différentes (17 joueurs →
  # [3, 3, 3, 3, 3, 2]). Le 1er de la poule de 2 ne dispute qu'UN match. Classer les
  # 1ers de poule sur des TOTAUX le condamne alors quoi qu'il fasse : invaincu, il
  # compte 1 victoire là où un 1er de poule de 3 tout aussi invaincu en compte 2.
  # Il hérite donc de la dernière tête de série des 1ers — donc du tour que les
  # mieux classés sautent — pour la seule raison qu'on lui a tiré un adversaire de
  # moins.
  #
  # Ce test compare les deux clés sur ce cas exact : #rank_key les sépare (c'est le
  # défaut), la clé normalisée les reconnaît à égalité de performance (2 points-
  # parties par match de part et d'autre). Les départages suivants (quotients,
  # draw_order) font le reste, et eux sont légitimes.
  test "seeding : deux 1ers de poule invaincus pèsent pareil, quelle que soit la taille de leur poule" do
    tournament = build_tournament(17, players_per_pool: 3)
    play_pools!(tournament)

    pools = standings_of(tournament)
    # Poules de 3 demandées, mais [3, 3, 3, 3, 3, 2] contiendrait une poule de 2,
    # interdite au Critérium : le découpage conforme le plus proche est [4, 4, 3, 3, 3].
    assert_equal [4, 4, 3, 3, 3], pools.values.map { |pool| pool.rows.size }.sort.reverse

    small = pools.values.find { |pool| pool.rows.size == 3 }
    big   = pools.values.find { |pool| pool.rows.size == 4 }

    small_first = small.qualifier(1)
    big_first   = big.qualifier(1)

    # Les deux sont invaincus, mais sur un nombre de matchs différent.
    assert_equal [2, 3], [small.row_for(small_first).played, big.row_for(big_first).played]
    assert_equal [4, 6], [small.row_for(small_first).points, big.row_for(big_first).points]

    flow = CriteriumFlow.new(Tournament.find(tournament.id))

    # Le défaut : sur les totaux, le 1er d'une poule de 3 est DERRIÈRE ceux des
    # poules de 4, et le tri global le relègue parmi les derniers des 1ers.
    fresh = Tournament.find(tournament.id)
    assert_operator fresh.rank_key(small_first).first, :>, fresh.rank_key(big_first).first,
                    "c'est bien le total brut qui pénalise la petite poule"
    firsts_by_total = pools.values.map { |pool| pool.qualifier(1) }.sort_by { |tu| fresh.rank_key(tu) }
    assert_equal 3, pools[firsts_by_total.last.pool].rows.size,
                 "au total brut, le dernier des 1ers vient toujours d'une poule de 3"

    # La correction : à performance PAR MATCH égale, les deux pèsent pareil.
    assert_equal flow.send(:pool_strength_key, small_first).first,
                 flow.send(:pool_strength_key, big_first).first,
                 "4 points en 2 matchs et 6 points en 3 matchs, c'est le même rendement"
  end
end
