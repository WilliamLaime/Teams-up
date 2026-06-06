# Tests d'intégration pour MessagesController
# Ce controller gère l'envoi de messages dans trois contextes différents :
#   1. Chat d'un match     → POST /matches/:match_id/messages
#   2. Chat d'une équipe   → POST /teams/:team_id/messages
#   3. Conversation privée → POST /private_conversations/:id/messages
# Le before_action set_context_and_check_access vérifie les droits avant create.
require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  # Helpers Devise pour simuler sign_in
  include Devise::Test::IntegrationHelpers

  # ─── Setup : données communes ────────────────────────────────────────────────
  setup do
    # Utilisateur principal (participant approuvé au match, captain de l'équipe)
    @user = create_test_user(email: "msg_user@example.com", first_name: "Alice", last_name: "Test")

    # Utilisateur étranger (ni inscrit au match, ni membre de l'équipe)
    @stranger = create_test_user(email: "msg_stranger@example.com", first_name: "Bob", last_name: "Test")

    # Sport nécessaire pour créer un match
    @sport = Sport.create!(name: "Football Messages", slug: "football-messages", icon: "⚽")

    # Match public dans le futur
    @match = Match.create!(
      title: "Match Messages Test",
      date: Date.tomorrow,
      time: Time.current.change(hour: 18, min: 0),
      player_left: 4,
      level: "Débutant",
      visibility: "public",
      validation_mode: "automatic",
      genre_restriction: "tous",
      user: @user,
      sport: @sport
    )

    # @user est organisateur et approuvé → droit d'écrire dans le chat
    @match.match_users.create!(user: @user, role: "organisateur", status: "approved")

    # Équipe avec @user comme capitaine
    # Note : after_create :add_captain_as_member ajoute automatiquement @user comme
    # TeamMember avec role "captain" — pas besoin de le créer manuellement
    @team = Team.create!(name: "Équipe Messages Test", captain: @user)

    # @team_member est le TeamMember créé automatiquement par after_create
    @team_member = @team.team_members.find_by(user: @user)

    # Conversation privée entre @user et @stranger
    @private_conv = PrivateConversation.create!(sender: @user, recipient: @stranger)
  end

  # Nettoie toutes les tables dans le bon ordre FK après chaque test
  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # POST /matches/:match_id/messages — message de match
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un participant approuvé peut envoyer un message dans le chat du match.
  # On attend un 200 OK avec Turbo Stream (format turbo_stream).
  test "POST /matches/:match_id/messages crée un message si l'utilisateur est participant approuvé" do
    sign_in @user
    assert_difference "Message.count", 1 do
      post match_messages_path(@match),
           params: { message: { content: "Bonjour à tous !" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    # Le message a bien été créé avec le bon contenu
    assert_equal "Bonjour à tous !", Message.last.content
  end

  # Cas d'erreur : un utilisateur non inscrit au match est redirigé vers le match
  # avec un message d'alerte (set_context_and_check_access le bloque).
  test "POST /matches/:match_id/messages redirige si l'utilisateur n'est pas participant" do
    sign_in @stranger
    assert_no_difference "Message.count" do
      post match_messages_path(@match),
           params: { message: { content: "Je n'ai pas le droit" } }
    end
    # Le controller redirige vers @match (match_path) avec un alert
    assert_redirected_to @match
  end

  # Cas d'erreur : un visiteur non connecté est redirigé vers root_path
  test "POST /matches/:match_id/messages redirige vers login pour un visiteur non connecté" do
    post match_messages_path(@match), params: { message: { content: "Intrus" } }
    assert_redirected_to new_user_session_path
  end

  # Edge case : un message avec contenu vide ne doit pas provoquer un 500
  # On vérifie simplement que le controller ne crashe pas
  test "POST /matches/:match_id/messages avec contenu vide ne crashe pas" do
    sign_in @user
    # Pas d'assert_difference car la validation peut refuser — on vérifie juste la réponse
    post match_messages_path(@match),
         params: { message: { content: "" } }
    # Le controller redirige avec alert ou retourne une réponse (pas un 500)
    assert_not_equal 500, response.status
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /teams/:team_id/messages — message d'équipe
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le captain (membre automatique via after_create) peut envoyer un message
  test "POST /teams/:team_id/messages crée un message si l'utilisateur est membre" do
    sign_in @user
    assert_difference "Message.count", 1 do
      post team_messages_path(@team),
           params: { message: { content: "Allez l'équipe !" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_equal "Allez l'équipe !", Message.last.content
  end

  # Cas d'erreur : un utilisateur non membre est redirigé vers la page de l'équipe
  test "POST /teams/:team_id/messages redirige si l'utilisateur n'est pas membre" do
    sign_in @stranger
    assert_no_difference "Message.count" do
      post team_messages_path(@team),
           params: { message: { content: "Je ne suis pas membre" } }
    end
    assert_redirected_to @team
  end

  # Cas d'erreur : visiteur non connecté → redirection root_path
  test "POST /teams/:team_id/messages redirige vers login pour un visiteur non connecté" do
    post team_messages_path(@team), params: { message: { content: "Intrus" } }
    assert_redirected_to new_user_session_path
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /private_conversations/:id/messages — message privé
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le sender peut envoyer un message dans la conversation privée
  test "POST /private_conversations/:id/messages crée un message si l'utilisateur est participant" do
    sign_in @user
    assert_difference "Message.count", 1 do
      post private_conversation_messages_path(@private_conv),
           params: { message: { content: "Message privé !" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_equal "Message privé !", Message.last.content
  end

  # Cas d'erreur : un tiers non participant est redirigé vers root_path
  test "POST /private_conversations/:id/messages redirige si l'utilisateur n'est pas participant" do
    # Crée un troisième utilisateur complètement étranger à la conversation
    third = create_test_user(email: "third@example.com", first_name: "Charlie", last_name: "Test")
    sign_in third
    assert_no_difference "Message.count" do
      post private_conversation_messages_path(@private_conv),
           params: { message: { content: "Accès refusé" } }
    end
    assert_redirected_to root_path
  end

  # Cas d'erreur : visiteur non connecté → redirection root_path
  test "POST /private_conversations/:id/messages redirige vers login pour un visiteur non connecté" do
    post private_conversation_messages_path(@private_conv),
         params: { message: { content: "Intrus" } }
    assert_redirected_to new_user_session_path
  end
end
