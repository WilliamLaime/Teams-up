require "test_helper"

# Tests du channel MatchChatChannel.
# Ce channel gère les notifications de frappe ("typing...") dans le chat d'un match.
#
# Comportements testés :
#   - Un participant approuvé peut s'abonner → stream créé
#   - Un non-participant est rejeté (reject)
#   - Un match inexistant entraîne un reject
#   - La méthode #typing diffuse le nom de l'utilisateur sur le stream du match
class MatchChatChannelTest < ActionCable::Channel::TestCase
  # Pas de parallélisation pour éviter les conflits de données partagées
  parallelize(workers: 1)

  # teardown_db gère l'ordre complet des FK (inclut Friendship, MatchUser, etc.)
  teardown { teardown_db }

  # ─── Helpers ────────────────────────────────────────────────────────────────

  # Crée un User avec profil complet.
  def make_user(email, first_name: "Chat", last_name: "User")
    create_test_user(email: email, first_name: first_name, last_name: last_name)
  end

  # Crée un Match avec tous les champs requis par les validations :
  #   - level: "Tout niveau" → passe level_valid_for_sport (backward compat)
  #   - players_needed: 5 → passe validates :player_left, greater_than: 0
  #   - date: Date.tomorrow + time futur → passe match_must_be_at_least_30min_in_future
  def make_match(user)
    sport = Sport.create!(
      name: "FootballCh#{SecureRandom.hex(3)}",
      icon: "⚽",
      slug: "football_ch_#{SecureRandom.hex(3)}"
    )
    Match.create!(
      user:        user,
      sport:       sport,
      date:        Date.tomorrow,
      time:        "15:00:00",
      place:       "Terrain de test",
      level:       "Tout niveau",
      players_needed: 5
    )
  end

  # Ajoute un MatchUser avec le statut et le rôle donnés.
  def add_match_user(match, user, status: "approved", role: "joueur")
    MatchUser.create!(match: match, user: user, status: status, role: role)
  end

  # ════════════════════════════════════════════════════════════════════════════
  # #subscribed
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un participant approuvé peut s'abonner au channel.
  # La souscription doit créer un stream nommé "match_chat_typing_<id>".
  test "subscribes un participant approuvé et crée le stream" do
    user  = make_user("match_chat_ok@example.com")
    match = make_match(user)
    add_match_user(match, user, status: "approved", role: "joueur")

    # stub_connection simule la connexion ActionCable avec current_user renseigné
    stub_connection current_user: user

    # subscribe déclenche la méthode subscribed du channel
    subscribe(match_id: match.id)

    # La souscription doit être confirmée (pas rejetée)
    assert subscription.confirmed?,
           "La souscription d'un participant approuvé doit être confirmée"

    # Un stream doit être ouvert sur le bon identifiant
    assert_has_stream "match_chat_typing_#{match.id}"
  end

  # Cas nominal : l'organisateur peut s'abonner (role = "organisateur").
  test "subscribes l'organisateur du match" do
    organizer = make_user("organizer_chat@example.com")
    match     = make_match(organizer)
    add_match_user(match, organizer, status: "pending", role: "organisateur")

    stub_connection current_user: organizer
    subscribe(match_id: match.id)

    assert subscription.confirmed?, "L'organisateur doit pouvoir s'abonner"
    assert_has_stream "match_chat_typing_#{match.id}"
  end

  # Cas d'erreur : un utilisateur non participant est rejeté.
  test "rejette un utilisateur non participant" do
    owner    = make_user("owner_chat@example.com")
    outsider = make_user("outsider_chat@example.com")
    match    = make_match(owner)
    add_match_user(match, owner, status: "approved", role: "organisateur")

    # outsider n'a pas de MatchUser → participant? retourne false → reject
    stub_connection current_user: outsider
    subscribe(match_id: match.id)

    assert subscription.rejected?,
           "Un non-participant doit être rejeté"
  end

  # Cas d'erreur : un match inexistant entraîne un reject.
  test "rejette si le match_id est inexistant" do
    user = make_user("no_match_chat@example.com")

    stub_connection current_user: user
    subscribe(match_id: 999999)

    assert subscription.rejected?,
           "Un match_id inexistant doit entraîner un reject"
  end

  # Cas d'erreur : un participant en attente (status: pending) est rejeté.
  test "rejette un participant en status pending" do
    user  = make_user("pending_chat@example.com")
    match = make_match(user)
    # Statut pending : n'est pas encore approuvé
    add_match_user(match, user, status: "pending", role: "joueur")

    stub_connection current_user: user
    subscribe(match_id: match.id)

    assert subscription.rejected?,
           "Un participant pending ne doit pas pouvoir s'abonner"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # #typing
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : typing diffuse le nom de l'utilisateur sur le stream du match.
  test "typing diffuse le display_name et l'id de l'utilisateur" do
    user  = make_user("typing_chat@example.com", first_name: "Typeur", last_name: "Chat")
    match = make_match(user)
    add_match_user(match, user, status: "approved", role: "joueur")

    stub_connection current_user: user
    subscribe(match_id: match.id)

    assert_broadcasts("match_chat_typing_#{match.id}", 1) do
      perform :typing, {}
    end
  end
end
