require "test_helper"

# Tests du moteur « Poules » (Lot 5) : répartition en poules, round-robin par poule
# (journée par journée), puis tableau final (qualifiés dynamiques pour remplir final_size).
class PoolBuilderTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Tennis test", slug: "tennis-test-#{SecureRandom.hex(4)}", icon: "🎾")
    @admin = create_test_user(email: "admin-#{SecureRandom.hex(4)}@test.fr")
  end

  def teardown
    teardown_db
  end

  def build_tournament(count)
    tournament = Tournament.create!(name: "T#{SecureRandom.hex(3)}", sport: @sport, user: @admin,
                                    format: "poules", status: "open", max_players: count,
                                    date: Date.tomorrow, place: "Terrain test")
    count.times do |i|
      user = create_test_user(email: "p#{i}-#{SecureRandom.hex(3)}@test.fr")
      tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    tournament
  end

  def resolve_current_round!(tournament)
    round = tournament.current_round
    round.tournament_matches.where(status: "pending", is_bye: false).find_each do |match|
      win_tournament_match!(match, match.player_a)
    end
    round
  end

  def play_to_completion!(tournament)
    100.times do
      break if tournament.reload.completed?

      resolve_current_round!(tournament)
      TournamentEngine.for(tournament).next_round!
    end
  end

  test "lancement : répartit en poules équilibrées (16 → 4 poules de 4)" do
    tournament = build_tournament(16)
    TournamentEngine.for(tournament).next_round!

    counts = tournament.tournament_users.players.group(:pool).count
    assert_equal [0, 1, 2, 3], counts.keys.sort
    assert_equal [4, 4, 4, 4], counts.values, "les 4 poules doivent avoir 4 joueurs chacune"
  end

  test "journée 1 : matchs de toutes les poules, positions uniques" do
    tournament = build_tournament(16)
    TournamentEngine.for(tournament).next_round!

    round = tournament.pool_rounds.first
    assert_equal 1, round.number
    assert_equal "pool", round.phase
    # 4 poules de 4 → 2 matchs par poule et par journée → 8 matchs.
    assert_equal 8, round.tournament_matches.count
    positions = round.tournament_matches.pluck(:position)
    assert_equal positions.uniq.sort, positions.sort, "positions uniques dans la ronde"
  end

  # Le round-robin est connu d'avance : tout le calendrier naît au lancement, pour
  # que chaque joueur voie ses 3 adversaires (et puisse convenir des dates avec eux)
  # au lieu d'un seul.
  test "lancement : TOUT le calendrier de poule est créé d'un coup" do
    tournament = build_tournament(16)
    TournamentEngine.for(tournament).next_round!

    assert_equal 3, tournament.pool_rounds.count, "poules de 4 → 3 journées d'emblée"
    # 4 poules × 2 matchs par journée × 3 journées = 24 confrontations.
    assert_equal 24, tournament.tournament_matches.count

    # Chaque joueur affronte bien les 3 autres de SA poule, une fois chacun.
    tournament.pools.each_value do |members|
      members.each do |player|
        opponents = tournament.tournament_matches
                              .where("player_a_id = :id OR player_b_id = :id", id: player.id)
                              .map { |m| m.player_a_id == player.id ? m.player_b_id : m.player_a_id }
        assert_equal (members.map(&:id) - [player.id]).sort, opponents.compact.sort
      end
    end
  end

  # La règle ne dépend pas de la taille : poule de 4 → 3 matchs, poule de 8 → 7.
  # C'est le round-robin intégral (LeagueBuilder.schedule), pas un nombre écrit en dur.
  test "poule de N joueurs : chacun joue N-1 matchs, quelle que soit la taille" do
    [3, 5, 8].each do |size|
      tournament = build_tournament(size)
      tournament.update!(players_per_pool: size) # une seule poule, de la taille voulue
      TournamentEngine.for(tournament).next_round!

      assert_equal 1, tournament.pools.size, "poule unique de #{size}"
      tournament.tournament_users.players.approved.each do |player|
        played = tournament.tournament_matches
                           .where(is_bye: false)
                           .where("player_a_id = :id OR player_b_id = :id", id: player.id)
        assert_equal size - 1, played.count,
                     "dans une poule de #{size}, chacun doit affronter les #{size - 1} autres"
      end
    end
  end

  test "idempotence : régénérer sans jouer ne crée aucune journée en double" do
    tournament = build_tournament(16)
    TournamentEngine.for(tournament).next_round!
    assert_equal 3, tournament.pool_rounds.count

    TournamentEngine.for(tournament).next_round!
    assert_equal 3, tournament.pool_rounds.count
  end

  # Ce que répare la migration BackfillMissingPoolRounds : un tournoi lancé AVANT
  # ce lot n'a que ses premières journées en base. Le moteur doit compléter le
  # calendrier sans toucher aux journées existantes ni aux scores déjà saisis —
  # c'est tout l'intérêt d'un rattrapage plutôt que d'un « tout créer ».
  test "rattrapage : un calendrier amputé se complète sans perdre les scores" do
    tournament = build_tournament(16)
    TournamentEngine.for(tournament).next_round!

    first = tournament.pool_rounds.first
    win_tournament_match!(first.tournament_matches.first, first.tournament_matches.first.player_a)
    kept = first.tournament_matches.first.winner_id

    # On simule l'ancien état : seule la journée 1 existe.
    tournament.pool_rounds.where.not(id: first.id).destroy_all
    assert_equal 1, tournament.reload.pool_rounds.count

    TournamentEngine.for(tournament).next_round!

    assert_equal 3, tournament.reload.pool_rounds.count
    assert_equal kept, first.reload.tournament_matches.first.winner_id,
                 "le rattrapage ne réécrit pas les rencontres déjà jouées"
    tournament.pools.each_value do |members|
      members.each do |player|
        played = tournament.tournament_matches.where(player_a: player).or(
          tournament.tournament_matches.where(player_b: player)
        ).joins(:tournament_round).where(tournament_rounds: { phase: "pool" })
        assert_equal members.size - 1, played.count
      end
    end
  end

  # Les journées ne sont plus une porte : un joueur peut saisir sa 3e confrontation
  # avant que la 1re journée soit finie, et sa carte ne doit pas se verrouiller pour
  # autant. La phase entière se verrouille d'un coup, à la dernière rencontre.
  test "les journées ne se verrouillent qu'une fois toute la phase de poules jouée" do
    tournament = build_tournament(16)
    TournamentEngine.for(tournament).next_round!

    last = tournament.pool_rounds.last
    last.tournament_matches.each { |m| win_tournament_match!(m, m.player_a) }
    TournamentEngine.for(tournament).next_round!

    assert_not_equal "completed", last.reload.status,
                     "une journée jouée en avance ne verrouille pas la phase"

    play_to_completion!(tournament)
    assert tournament.pool_rounds.all? { |r| r.status == "completed" }
  end

  test "flux complet 16 joueurs → 3 journées → 8 qualifiés → Final 8 → completed" do
    tournament = build_tournament(16)
    TournamentEngine.for(tournament).next_round!
    play_to_completion!(tournament)

    assert tournament.reload.completed?, "le tournoi doit être terminé"
    assert_equal 3, tournament.pool_rounds.count, "4 joueurs par poule → 3 journées"
    assert tournament.bracket_started?
    # final_size 8 (> 8 joueurs) → 8 finalistes marqués qualified.
    assert_equal 8, tournament.tournament_users.qualified.count
    final = tournament.bracket_rounds.last
    assert_equal 1, final.tournament_matches.count
  end

  test "32 joueurs : 8 poules de 4, top 2 par poule qualifiés → huitièmes (16 places)" do
    tournament = build_tournament(32)
    TournamentEngine.for(tournament).next_round!

    counts = tournament.tournament_users.players.group(:pool).count
    assert_equal (0..7).to_a, counts.keys.sort
    assert_equal [4] * 8, counts.values, "8 poules de 4 joueurs"

    play_to_completion!(tournament)

    assert tournament.reload.bracket_started?
    assert_equal 16, tournament.final_size, "top 2 de chaque poule (8 poules) → huitièmes"
    assert_equal 16, tournament.tournament_users.qualified.count

    tournament.pools.each_value do |members|
      qualified_in_pool = members.count(&:qualified?)
      assert_equal 2, qualified_in_pool, "exactement 2 qualifiés par poule"
    end

    first_bracket_round = tournament.bracket_rounds.find_by(number: 1)
    assert_equal 8, first_bracket_round.tournament_matches.count, "16 places → 8 matchs en huitièmes"
  end
end
