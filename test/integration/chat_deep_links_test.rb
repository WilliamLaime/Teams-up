require "test_helper"

# Tests des liens « ouvrir directement la discussion » (mails et notifications
# de chat, cf. ChatEmailDigest#chat_path).
#
# Règles :
#   - la page n'ouvre le chat (contrôleur Stimulus modal-autoopen) que pour un
#     utilisateur qui y a accès ;
#   - sur une page publique (match, tournoi), un visiteur non connecté est
#     d'abord envoyé vers la connexion — le chat n'y est pas visible sinon.
class ChatDeepLinksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  AUTOOPEN = 'data-controller="modal-autoopen"'.freeze

  teardown { teardown_db }

  setup do
    @alice = create_test_user(email: "link-alice@example.com", first_name: "Alice", last_name: "Martin")
    @bob   = create_test_user(email: "link-bob@example.com", first_name: "Bob", last_name: "Durand")
    @stranger = create_test_user(email: "link-stranger@example.com")
  end

  # ── Match ──────────────────────────────────────────────────────────────────

  def create_match
    sport = Sport.create!(name: "Foot Link", slug: "foot-link", icon: "⚽")
    match = Match.create!(title: "Foot du jeudi", place: "Stade", date: Date.tomorrow, time: 2.hours.from_now,
                          players_needed: 10, level: "Tout niveau", user: @alice, sport: sport)
    match.match_users.create!(user: @alice, role: "organisateur", status: "approved")
    match
  end

  test "match : un visiteur non connecté est envoyé vers la connexion" do
    get match_path(create_match, open_chat: 1)

    assert_redirected_to new_user_session_path
  end

  test "match : sans le paramètre, la page reste publique" do
    get match_path(create_match)

    assert_response :success
  end

  test "match : le participant arrive avec le chat ouvert" do
    match = create_match
    sign_in @alice

    get match_path(match, open_chat: 1)

    assert_response :success
    assert_includes response.body, AUTOOPEN
  end

  test "match : un non-participant n'a pas de chat à ouvrir" do
    match = create_match
    sign_in @stranger

    get match_path(match, open_chat: 1)

    assert_not_includes response.body, AUTOOPEN
  end

  # ── Équipe ─────────────────────────────────────────────────────────────────

  test "équipe : un membre arrive avec le chat ouvert" do
    team = Team.create!(name: "Les Liens", captain: @alice)
    sign_in @alice

    get team_path(team, open_chat: 1)

    assert_response :success
    assert_includes response.body, AUTOOPEN
  end

  # ── Match de tournoi ───────────────────────────────────────────────────────

  def create_tournament_match
    sport = Sport.create!(name: "Padel Link", slug: "padel-link", icon: "🎾")
    @tournament = Tournament.create!(name: "Open", sport: sport, user: create_test_user(email: "link-admin@example.com"),
                                     format: "ronde_suisse", status: "in_progress", max_players: 8,
                                     date: Date.tomorrow, place: "Club")
    round = @tournament.tournament_rounds.create!(phase: "swiss", number: 1)
    player_a = @tournament.tournament_users.create!(user: @alice, role: "joueur", status: "approved")
    player_b = @tournament.tournament_users.create!(user: @bob, role: "joueur", status: "approved")
    round.tournament_matches.create!(player_a: player_a, player_b: player_b, position: 0)
  end

  test "tournoi : un joueur du match arrive sur l'onglet Matchs avec son chat chargé" do
    tmatch = create_tournament_match
    sign_in @bob

    get tournament_path(@tournament, tmatch_chat: tmatch.id)

    assert_response :success
    assert_includes response.body, AUTOOPEN
    assert_includes response.body, tournament_match_conversation_path(tmatch)
  end

  test "tournoi : un tiers n'ouvre pas le chat d'une confrontation" do
    tmatch = create_tournament_match
    sign_in @stranger

    get tournament_path(@tournament, tmatch_chat: tmatch.id)

    assert_response :success
    assert_not_includes response.body, AUTOOPEN
  end

  test "tournoi : un visiteur non connecté est envoyé vers la connexion" do
    tmatch = create_tournament_match

    get tournament_path(@tournament, tmatch_chat: tmatch.id)

    assert_redirected_to new_user_session_path
  end
end
