require "test_helper"

# Autorisations de saisie du score (Lot 4) : ouvertes à l'admin, aux
# co-organisateurs et aux deux joueurs du match, tant que le tour n'est pas verrouillé.
class TournamentMatchPolicyTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Padel test", slug: "padel-test-#{SecureRandom.hex(4)}", icon: "🎾")
    @admin = create_test_user(email: "admin-#{SecureRandom.hex(3)}@t.fr")
    @tournament = Tournament.create!(name: "T", sport: @sport, format: "ronde_suisse",
                                     status: "in_progress", user: @admin,
                                     max_players: 8, date: Date.tomorrow, place: "Terrain test")
    @round = @tournament.tournament_rounds.create!(phase: "swiss", number: 1, status: "in_progress")

    @player_a = enroll("pa")
    @player_b = enroll("pb")
    @co_org   = enroll_co_org("co")
    @stranger = create_test_user(email: "stranger-#{SecureRandom.hex(3)}@t.fr")

    @match = @round.tournament_matches.create!(player_a: @player_a, player_b: @player_b, position: 0)
  end

  def teardown
    teardown_db
  end

  def enroll(tag)
    user = create_test_user(email: "#{tag}-#{SecureRandom.hex(3)}@t.fr")
    @tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
  end

  def enroll_co_org(tag)
    user = create_test_user(email: "#{tag}-#{SecureRandom.hex(3)}@t.fr")
    @tournament.tournament_users.create!(user: user, role: "co_organisateur", status: "approved")
    user
  end

  def test_admin_peut_saisir
    assert TournamentMatchPolicy.new(@admin, @match).update?
  end

  def test_co_organisateur_peut_saisir
    assert TournamentMatchPolicy.new(@co_org, @match).update?
  end

  def test_joueurs_du_match_peuvent_saisir
    assert TournamentMatchPolicy.new(@player_a.user, @match).update?
    assert TournamentMatchPolicy.new(@player_b.user, @match).update?
  end

  def test_tiers_ne_peut_pas_saisir
    refute TournamentMatchPolicy.new(@stranger, @match).update?
  end

  def test_visiteur_non_connecte_refuse
    refute TournamentMatchPolicy.new(nil, @match).update?
  end

  def test_tour_verrouille_refuse_meme_admin
    @round.update!(status: "completed")
    refute TournamentMatchPolicy.new(@admin, @match).update?
    refute TournamentMatchPolicy.new(@player_a.user, @match).update?
  end

  def test_show_public
    assert TournamentMatchPolicy.new(nil, @match).show?
  end
end
