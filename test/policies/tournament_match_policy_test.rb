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

  # ── create_match? (Lot 7) : planifier la rencontre réelle ───────────────────
  def test_joueurs_et_organisateurs_peuvent_creer_la_rencontre
    assert TournamentMatchPolicy.new(@player_a.user, @match).create_match?
    assert TournamentMatchPolicy.new(@player_b.user, @match).create_match?
    assert TournamentMatchPolicy.new(@admin, @match).create_match?
    assert TournamentMatchPolicy.new(@co_org, @match).create_match?
  end

  def test_tiers_et_visiteur_ne_peuvent_pas_creer_la_rencontre
    refute TournamentMatchPolicy.new(@stranger, @match).create_match?
    refute TournamentMatchPolicy.new(nil, @match).create_match?
  end

  def test_pas_de_rencontre_pour_un_bye
    bye = @round.tournament_matches.create!(player_a: @player_a, is_bye: true, position: 1)
    refute TournamentMatchPolicy.new(@player_a.user, bye).create_match?
  end

  # Index unique sur matches.tournament_match_id : une seule rencontre par
  # confrontation. Le 2e joueur ne doit donc plus voir « Créer la rencontre ».
  def test_confrontation_deja_rattachee
    Match.create!(user: @player_a.user, sport: @sport, tournament: @tournament, tournament_match: @match,
                  title: "Rencontre", date: Date.tomorrow, time: Time.current, end_time: 1.hour.from_now,
                  place: "Terrain test", level: "Tout niveau", players_needed: 2, validation_mode: "automatic")

    refute TournamentMatchPolicy.new(@player_b.user, @match.reload).create_match?
    refute TournamentMatchPolicy.new(@admin, @match).create_match?
  end

  # Le verrou de tour ne concerne QUE la saisie de score : une rencontre peut
  # toujours être planifiée (ex. match à rejouer, ou création tardive).
  def test_tour_verrouille_n_empeche_pas_la_creation
    @round.update!(status: "completed")
    assert TournamentMatchPolicy.new(@player_a.user, @match).create_match?
  end
end
