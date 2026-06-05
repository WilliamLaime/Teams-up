# Tests d'intégration pour ConversationsController
# Ce controller gère le chat des matchs dans le panneau sticky latéral.
# Les routes testées :
#   GET    /conversations/:id         → affiche le chat d'un match
#   DELETE /conversations/:id/dismiss → masque la conversation dans la sidebar
require "test_helper"

class ConversationsControllerTest < ActionDispatch::IntegrationTest
  # Helpers Devise pour simuler un utilisateur connecté via sign_in
  include Devise::Test::IntegrationHelpers

  # ─── Setup : données communes à tous les tests ──────────────────────────────
  setup do
    # Utilisateur participant au match (organisateur)
    @user = create_test_user(email: "chat_owner@example.com", first_name: "Alice", last_name: "Test")

    # Deuxième utilisateur qui n'est PAS inscrit au match
    @other_user = create_test_user(email: "chat_stranger@example.com", first_name: "Bob", last_name: "Test")

    # Sport nécessaire pour créer un match
    @sport = Sport.create!(name: "Football Chat", slug: "football-chat", icon: "⚽")

    # Match public dans le futur
    @match = Match.create!(
      title: "Match Chat Test",
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

    # @user est organisateur et approuvé → il a le droit d'accéder au chat
    @match.match_users.create!(user: @user, role: "organisateur", status: "approved")
  end

  # Nettoie toutes les tables dans le bon ordre FK après chaque test
  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # GET /conversations/:id — action show
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un utilisateur inscrit et approuvé au match peut voir le chat.
  # On attend un 200 OK car le match existe et l'utilisateur est participant.
  test "GET /conversations/:id retourne 200 si l'utilisateur est participant approuvé" do
    sign_in @user
    get conversation_path(@match)
    # L'utilisateur est organisateur avec status approved → accès autorisé
    assert_response :success
  end

  # Cas d'erreur : un visiteur non connecté est redirigé vers root_path.
  # ApplicationController#redirect_to_landing_if_visitor intercepte avant Devise.
  test "GET /conversations/:id redirige vers root pour un visiteur non connecté" do
    get conversation_path(@match)
    assert_redirected_to root_path
  end

  # Edge case : un utilisateur connecté mais NON inscrit au match reçoit 403.
  # Le controller renvoie head :forbidden si match_user est nil ou non approuvé.
  test "GET /conversations/:id retourne 403 si l'utilisateur n'est pas inscrit au match" do
    sign_in @other_user
    get conversation_path(@match)
    assert_response :forbidden
  end

  # Edge case : si le match n'existe pas (id inconnu), le controller rend un message
  # inline plutôt que de crasher avec une exception ActiveRecord::RecordNotFound.
  test "GET /conversations/:id retourne 200 avec message vide si le match n'existe pas" do
    sign_in @user
    get conversation_path(id: 999999)
    # find_by(id: params[:id]) retourne nil → render inline → pas de crash
    assert_response :success
  end

  # ════════════════════════════════════════════════════════════════════════════
  # DELETE /conversations/:id/dismiss — action dismiss
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un participant peut masquer sa conversation.
  # On vérifie la redirection HTML (pas Turbo Stream dans ce test).
  test "DELETE /conversations/:id/dismiss masque la conversation et redirige" do
    sign_in @user
    # On utilise le format HTML pour obtenir une redirection (pas un Turbo Stream)
    delete dismiss_conversation_path(@match)
    # Le controller fait redirect_back avec fallback root_path
    assert_redirected_to root_path

    # Vérifie que chat_dismissed_at a bien été posé
    match_user = @match.match_users.find_by(user: @user)
    assert_not_nil match_user.chat_dismissed_at
  end

  # Cas d'erreur : un visiteur non connecté est redirigé vers root_path.
  test "DELETE /conversations/:id/dismiss redirige vers root pour un visiteur non connecté" do
    delete dismiss_conversation_path(@match)
    assert_redirected_to root_path
  end

  # Edge case : si le match n'existe pas, le controller répond 404 (head :not_found).
  test "DELETE /conversations/:id/dismiss retourne 404 si le match n'existe pas" do
    sign_in @user
    delete dismiss_conversation_path(id: 999999)
    assert_response :not_found
  end
end
