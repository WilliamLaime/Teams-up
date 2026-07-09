require "test_helper"

class TournamentMatchTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Padel test", slug: "padel-test-#{SecureRandom.hex(4)}", icon: "🎾")
    @tournament = Tournament.create!(name: "T", sport: @sport, format: "ronde_suisse", status: "in_progress")
    @round = @tournament.tournament_rounds.create!(phase: "swiss", number: 1, status: "in_progress")
    @a = tu("a")
    @b = tu("b")
    @c = tu("c")
  end

  def teardown
    teardown_db
  end

  def tu(tag)
    user = create_test_user(email: "#{tag}-#{SecureRandom.hex(3)}@test.fr")
    @tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
  end

  test "le vainqueur doit être l'un des deux joueurs du match" do
    match = @round.tournament_matches.new(player_a: @a, player_b: @b, position: 0, winner: @c)
    assert_not match.valid?
    assert_includes match.errors[:winner], "doit être l'un des deux joueurs du match"
  end

  test "vainqueur valide accepté" do
    match = @round.tournament_matches.new(player_a: @a, player_b: @b, position: 0, winner: @b)
    assert match.valid?
  end

  test "bye : player_a gagne d'office et le match est clôturé" do
    match = @round.tournament_matches.create!(player_a: @a, is_bye: true, position: 0)
    assert_nil match.player_b_id
    assert_equal @a.id, match.winner_id
    assert_equal "completed", match.status
    assert match.decided?
  end

  test "loser renvoie l'adversaire du vainqueur (nil sur un bye)" do
    match = @round.tournament_matches.create!(player_a: @a, player_b: @b, position: 0, winner: @a, status: "completed")
    assert_equal @b.id, match.loser.id

    bye = @round.tournament_matches.create!(player_a: @c, is_bye: true, position: 1)
    assert_nil bye.loser
  end
end
