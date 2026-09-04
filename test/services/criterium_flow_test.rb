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
    assert_equal 6, pools.size, "17 joueurs en poules de 3 doivent donner [3, 3, 3, 3, 3, 2]"

    small = pools.values.find { |pool| pool.rows.size == 2 }
    big   = pools.values.find { |pool| pool.rows.size == 3 }
    assert small, "il doit exister une poule de 2"

    small_first = small.qualifier(1)
    big_first   = big.qualifier(1)

    # Les deux sont invaincus, mais sur un nombre de matchs différent.
    assert_equal [1, 2], [small.row_for(small_first).played, big.row_for(big_first).played]
    assert_equal [2, 4], [small.row_for(small_first).points, big.row_for(big_first).points]

    flow = CriteriumFlow.new(Tournament.find(tournament.id))

    # Le défaut : sur les totaux, le 1er de la poule de 2 est DERRIÈRE, et le tri
    # global le relègue au dernier rang des 1ers de poule.
    fresh = Tournament.find(tournament.id)
    assert_operator fresh.rank_key(small_first).first, :>, fresh.rank_key(big_first).first,
                    "c'est bien le total brut qui pénalise la poule de 2"
    firsts_by_total = (1..6).filter_map { |i| pools[i - 1]&.qualifier(1) }
                            .sort_by { |tu| fresh.rank_key(tu) }
    assert_equal small_first.id, firsts_by_total.last.id,
                 "au total brut, le 1er de la poule de 2 est toujours le dernier des 1ers"

    # La correction : à performance PAR MATCH égale, les deux pèsent pareil.
    assert_equal flow.send(:pool_strength_key, small_first).first,
                 flow.send(:pool_strength_key, big_first).first,
                 "2 points en 1 match et 4 points en 2 matchs, c'est le même rendement"
  end
end
