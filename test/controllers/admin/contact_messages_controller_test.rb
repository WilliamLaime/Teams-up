# Tests d'intégration pour Admin::ContactMessagesController
# Ce controller gère les messages reçus via le formulaire /contact.
# Actions testées : index, toggle_lu, mark_read, reply, destroy, destroy_all
#
# PROBLÈME DNS : ContactMessage valide l'email via ValidEmail2 (lookup MX DNS).
# Si le domaine de l'email n'a pas d'enregistrement MX, update() échoue silencieusement
# car la validation Rails est déclenchée MÊME sur les updates.
#
# SOLUTION : on monkey-patche ValidEmail2::Address#valid_mx? pour retourner true
# dans le contexte de ces tests uniquement (classe ouverte, isolation par fichier).
# C'est plus robuste que de dépendre du DNS réel (brittle en CI).
require "test_helper"

# ── Patch de test : neutralise la vérification DNS de valid_email2 ─────────────
# On ouvre ValidEmail2::Address uniquement dans ce fichier de test.
# valid_mx? retourne toujours true pour éviter les appels DNS en test.
# Ceci est sûr car on ne teste pas la validation d'email ici — on teste le controller.
module ValidEmail2
  class Address
    # Remplace la vérification MX par un retour statique true en test
    def valid_mx?
      true
    end
  end
end

class Admin::ContactMessagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # ─── Setup ────────────────────────────────────────────────────────────────
  setup do
    # Admin : flag admin forcé en base via update_column (bypass callbacks)
    @admin = create_test_user(email: "admin@example.com", first_name: "Admin", last_name: "User")
    @admin.update_column(:admin, true)

    # Non-admin
    @user = create_test_user(email: "user@example.com", first_name: "Normal", last_name: "User")

    # On crée un ContactMessage via create! (le patch valid_mx? ci-dessus permet ça)
    # Le domaine example.com n'a pas de MX réel, mais valid_mx? retourne toujours true
    @contact_message = ContactMessage.create!(
      prenom:  "Jean",
      nom:     "Dupont",
      email:   "jean@example.com",
      sujet:   "Test",
      message: "Bonjour, ceci est un message de test.",
      lu:      false
    )
  end

  # ─── Teardown ─────────────────────────────────────────────────────────────
  teardown do
    ContactMessage.delete_all
    teardown_db
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /admin/contact_messages — index
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : l'admin peut voir la liste des messages de contact
  test "GET /admin/contact_messages retourne 200 pour un admin" do
    sign_in @admin

    get admin_contact_messages_path

    assert_response :success
  end

  # Cas d'erreur : un non-admin est redirigé
  test "GET /admin/contact_messages redirige un non-admin" do
    sign_in @user

    get admin_contact_messages_path

    assert_redirected_to root_path
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /admin/contact_messages/:id/toggle_lu — bascule lu/non-lu
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : bascule un message non-lu → lu
  test "PATCH toggle_lu passe le message de non-lu à lu" do
    sign_in @admin

    # Le message est créé avec lu: false
    assert_equal false, @contact_message.lu

    patch toggle_lu_admin_contact_message_path(@contact_message)

    # Après toggle, le message doit être marqué comme lu
    @contact_message.reload
    assert_equal true, @contact_message.lu

    # Et on est redirigé vers la liste
    assert_redirected_to admin_contact_messages_path
  end

  # Cas edge : un deuxième toggle repasse lu → non-lu
  test "PATCH toggle_lu repasse le message de lu à non-lu" do
    sign_in @admin

    # On marque d'abord comme lu (update_column bypass validations pour le setup)
    @contact_message.update_column(:lu, true)
    assert_equal true, @contact_message.lu

    patch toggle_lu_admin_contact_message_path(@contact_message)

    # Après le deuxième toggle, doit repasser à non-lu
    @contact_message.reload
    assert_equal false, @contact_message.lu

    assert_redirected_to admin_contact_messages_path
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /admin/contact_messages/:id/mark_read — marque comme lu
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : mark_read passe lu à true et redirige en HTML (fallback)
  test "PATCH mark_read marque le message comme lu" do
    sign_in @admin

    # Message non lu au départ
    assert_equal false, @contact_message.lu

    # On envoie une requête HTML (pas Turbo Stream) pour tester le fallback redirect
    patch mark_read_admin_contact_message_path(@contact_message)

    @contact_message.reload
    assert_equal true, @contact_message.lu

    # Fallback HTML → redirection vers la liste
    assert_redirected_to admin_contact_messages_path
  end

  # Cas edge : mark_read sur un message déjà lu ne lève pas d'erreur
  test "PATCH mark_read sur un message déjà lu ne change rien" do
    sign_in @admin

    # Message déjà lu (update_column bypass la validation pour le setup)
    @contact_message.update_column(:lu, true)

    # Ne doit pas planter — le controller vérifie `unless @contact_message.lu?`
    patch mark_read_admin_contact_message_path(@contact_message)

    assert_response :redirect
    @contact_message.reload
    assert_equal true, @contact_message.lu
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /admin/contact_messages/:id/reply — envoie une réponse par email
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : une réponse non vide est acceptée, marque lu et redirige
  test "POST reply avec un corps valide redirige avec notice" do
    sign_in @admin

    # deliver_later utilise l'adapter :test en environnement de test (pas de vrai envoi)
    post reply_admin_contact_message_path(@contact_message),
         params: { reply_body: "Bonjour, merci de votre message." }

    # Le message doit être marqué comme lu après la réponse
    @contact_message.reload
    assert_equal true, @contact_message.lu

    # Redirection vers la liste avec un message de confirmation
    assert_redirected_to admin_contact_messages_path
    assert_match "Réponse envoyée", flash[:notice]
  end

  # Cas d'erreur : une réponse vide est rejetée avec une alerte
  test "POST reply avec un corps vide redirige avec alerte" do
    sign_in @admin

    post reply_admin_contact_message_path(@contact_message),
         params: { reply_body: "   " }

    # Le controller vérifie reply_body.blank? et rejette
    assert_redirected_to admin_contact_messages_path
    assert_match "ne peut pas être vide", flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # DELETE /admin/contact_messages/:id — supprime un message
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un message est supprimé et on est redirigé
  test "DELETE /admin/contact_messages/:id supprime le message" do
    sign_in @admin

    count_before = ContactMessage.count

    # On envoie en HTML (pas Turbo) pour obtenir le fallback redirect
    delete admin_contact_message_path(@contact_message)

    # La base doit avoir un enregistrement de moins
    assert_equal count_before - 1, ContactMessage.count

    assert_redirected_to admin_contact_messages_path
  end

  # ════════════════════════════════════════════════════════════════════════════
  # DELETE /admin/contact_messages/destroy_all — supprime TOUS les messages
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : tous les messages sont supprimés d'un coup
  test "DELETE destroy_all supprime tous les messages" do
    sign_in @admin

    # On ajoute un deuxième message pour vérifier que les deux sont supprimés
    ContactMessage.create!(
      prenom: "Marie", nom: "Martin", email: "marie@example.com",
      sujet: "Autre test", message: "Un deuxième message.", lu: false
    )

    assert ContactMessage.count >= 2

    delete destroy_all_admin_contact_messages_path

    # Après destroy_all, la table doit être vide
    assert_equal 0, ContactMessage.count

    assert_redirected_to admin_contact_messages_path
    assert_match "supprimés", flash[:notice]
  end

  # Cas edge : destroy_all sur table vide ne lève pas d'erreur
  test "DELETE destroy_all sur table vide ne plante pas" do
    sign_in @admin

    ContactMessage.delete_all

    # Ne doit pas lever d'exception même si la table est vide
    delete destroy_all_admin_contact_messages_path

    assert_equal 0, ContactMessage.count
    assert_redirected_to admin_contact_messages_path
  end
end
