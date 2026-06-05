# Tests d'intégration pour PrivateConversationsController
# Ce controller gère les conversations privées (1-to-1) entre deux utilisateurs.
# Routes testées :
#   POST   /private_conversations             → crée ou retrouve une conversation
#   GET    /private_conversations/:id         → affiche le chat
#   PATCH  /private_conversations/:id/mark_read → marque comme lu
#   DELETE /private_conversations/:id/dismiss   → masque la conversation
require "test_helper"

class PrivateConversationsControllerTest < ActionDispatch::IntegrationTest
  # Helpers Devise pour simuler sign_in
  include Devise::Test::IntegrationHelpers

  # ─── Setup : données communes ────────────────────────────────────────────────
  setup do
    # L'expéditeur qui initie la conversation
    @sender = create_test_user(email: "priv_sender@example.com", first_name: "Alice", last_name: "Test")

    # Le destinataire
    @recipient = create_test_user(email: "priv_recipient@example.com", first_name: "Bob", last_name: "Test")

    # Un troisième utilisateur complètement étranger à la conversation
    @stranger = create_test_user(email: "priv_stranger@example.com", first_name: "Charlie", last_name: "Test")

    # Une conversation privée existante entre sender et recipient
    @conversation = PrivateConversation.create!(sender: @sender, recipient: @recipient)
  end

  # Nettoie toutes les tables dans le bon ordre FK après chaque test
  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # POST /private_conversations — action create
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : crée une nouvelle conversation et redirige vers le profil
  # du destinataire avec le paramètre open_chat contenant l'id de la conversation.
  test "POST /private_conversations crée ou retrouve une conversation et redirige" do
    sign_in @sender
    # On supprime la conversation existante pour tester la création
    @conversation.destroy
    post private_conversations_path, params: { recipient_id: @recipient.id }

    # Le controller redirige vers user_profil_path(@other_user, open_chat: conversation.id)
    # On vérifie juste que c'est une redirection (code 3xx)
    assert_response :redirect
    # Vérifie qu'une conversation a bien été créée entre les deux utilisateurs
    assert PrivateConversation.between(@sender, @recipient).persisted?
  end

  # Cas nominal bis : si la conversation existe déjà, on la retrouve (pas de doublon)
  test "POST /private_conversations retrouve la conversation existante sans créer de doublon" do
    sign_in @sender
    assert_no_difference "PrivateConversation.count" do
      post private_conversations_path, params: { recipient_id: @recipient.id }
    end
  end

  # Cas d'erreur : un visiteur non connecté est redirigé vers root_path.
  test "POST /private_conversations redirige vers root pour un visiteur non connecté" do
    post private_conversations_path, params: { recipient_id: @recipient.id }
    assert_redirected_to root_path
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /private_conversations/:id — action show
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : l'expéditeur peut voir la conversation → 200 OK
  test "GET /private_conversations/:id retourne 200 pour le sender" do
    sign_in @sender
    get private_conversation_path(@conversation)
    assert_response :success
  end

  # Cas nominal bis : le destinataire peut également voir la conversation
  test "GET /private_conversations/:id retourne 200 pour le recipient" do
    sign_in @recipient
    get private_conversation_path(@conversation)
    assert_response :success
  end

  # Cas d'erreur : un utilisateur étranger à la conversation reçoit un 403.
  # Le controller vérifie que current_user est sender ou recipient.
  test "GET /private_conversations/:id retourne 403 pour un utilisateur non participant" do
    sign_in @stranger
    get private_conversation_path(@conversation)
    assert_response :forbidden
  end

  # Cas d'erreur : un visiteur non connecté est redirigé vers root_path.
  test "GET /private_conversations/:id redirige vers root pour un visiteur non connecté" do
    get private_conversation_path(@conversation)
    assert_redirected_to root_path
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /private_conversations/:id/mark_read — action mark_read
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un participant marque la conversation comme lue → 200 OK
  # Le controller appelle mark_read_for!(current_user) et répond head :ok
  test "PATCH mark_read retourne 200 pour un participant" do
    sign_in @sender
    patch mark_read_private_conversation_path(@conversation)
    assert_response :ok

    # Vérifie que sender_last_read_at a bien été mis à jour
    @conversation.reload
    assert_not_nil @conversation.sender_last_read_at
  end

  # Cas d'erreur : un utilisateur étranger reçoit un 403
  test "PATCH mark_read retourne 403 pour un non-participant" do
    sign_in @stranger
    patch mark_read_private_conversation_path(@conversation)
    assert_response :forbidden
  end

  # Cas d'erreur : visiteur non connecté → redirection root_path
  test "PATCH mark_read redirige vers root pour un visiteur non connecté" do
    patch mark_read_private_conversation_path(@conversation)
    assert_redirected_to root_path
  end

  # ════════════════════════════════════════════════════════════════════════════
  # DELETE /private_conversations/:id/dismiss — action dismiss
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le sender peut masquer la conversation → redirige (format HTML)
  test "DELETE dismiss masque la conversation pour le sender et redirige" do
    sign_in @sender
    delete dismiss_private_conversation_path(@conversation)
    # Redirection HTML (pas Turbo Stream dans ce test)
    assert_redirected_to root_path

    # Vérifie que sender_dismissed_at a bien été posé
    @conversation.reload
    assert_not_nil @conversation.sender_dismissed_at
  end

  # Cas d'erreur : un utilisateur étranger reçoit 403
  test "DELETE dismiss retourne 403 pour un non-participant" do
    sign_in @stranger
    delete dismiss_private_conversation_path(@conversation)
    assert_response :forbidden
  end

  # Cas d'erreur : visiteur non connecté → redirection root_path
  test "DELETE dismiss redirige vers root pour un visiteur non connecté" do
    delete dismiss_private_conversation_path(@conversation)
    assert_redirected_to root_path
  end
end
