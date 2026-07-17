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

  test "idempotence : régénérer sans terminer la journée ne crée rien" do
    tournament = build_tournament(16)
    TournamentEngine.for(tournament).next_round!
    assert_equal 1, tournament.pool_rounds.count

    TournamentEngine.for(tournament).next_round!
    assert_equal 1, tournament.pool_rounds.count
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
end
