# Tests d'intégration pour PushSubscriptionsController
# Ce controller gère les subscriptions Web Push pour les notifications navigateur.
# Appelé par le Stimulus controller push_notification_controller.js.
# Routes testées :
#   POST   /push_subscriptions → crée une subscription (find_or_create)
#   DELETE /push_subscriptions → supprime la subscription pour l'endpoint fourni
require "test_helper"

class PushSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  # Helpers Devise pour simuler sign_in
  include Devise::Test::IntegrationHelpers

  # ─── Setup : données communes ────────────────────────────────────────────────
  setup do
    # Utilisateur connecté qui va créer/supprimer des subscriptions
    @user = create_test_user(email: "push_user@example.com", first_name: "Alice", last_name: "Test")

    # Données de subscription valides (format envoyé par le navigateur via l'API Web Push)
    @valid_subscription_params = {
      subscription: {
        endpoint: "https://fcm.googleapis.com/fcm/send/test-endpoint-123",
        p256dh:   "BNcRdreALRFXTkOOUHK1EtK2wtaz5Ry4YfYCA_0QTpQtUbVlTpCrQlLXXuU3HZ9c_DPtCEMcCO",
        auth:     "tBHItJI5svbpez7KI4CCXg"
      }
    }
  end

  # Nettoie toutes les tables dans le bon ordre FK après chaque test
  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # POST /push_subscriptions — action create
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : crée une nouvelle subscription pour l'utilisateur connecté
  # Le controller utilise find_or_initialize_by pour éviter les doublons (même endpoint)
  test "POST /push_subscriptions crée une subscription si connecté" do
    sign_in @user
    assert_difference "PushSubscription.count", 1 do
      post push_subscriptions_path, params: @valid_subscription_params
    end

    # Le controller répond { status: "ok" } avec code 200
    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "ok", json["status"]
  end

  # Cas nominal : si la subscription avec le même endpoint existe déjà, elle est mise à jour
  # (find_or_initialize_by → pas de création en doublon)
  test "POST /push_subscriptions met à jour une subscription existante sans créer de doublon" do
    sign_in @user
    # Crée d'abord la subscription
    @user.push_subscriptions.create!(
      endpoint: @valid_subscription_params[:subscription][:endpoint],
      p256dh:   "ancienne_clé",
      auth:     "ancien_auth"
    )

    assert_no_difference "PushSubscription.count" do
      post push_subscriptions_path, params: @valid_subscription_params
    end

    assert_response :ok
    # Vérifie que les clés ont été mises à jour
    sub = @user.push_subscriptions.find_by(endpoint: @valid_subscription_params[:subscription][:endpoint])
    assert_equal @valid_subscription_params[:subscription][:p256dh], sub.p256dh
  end

  # Cas d'erreur : un visiteur non connecté est redirigé vers root_path
  # (redirect_to_landing_if_visitor + authenticate_user! bloquent les visiteurs)
  test "POST /push_subscriptions redirige vers root pour un visiteur non connecté" do
    post push_subscriptions_path, params: @valid_subscription_params
    assert_redirected_to root_path
  end

  # ════════════════════════════════════════════════════════════════════════════
  # DELETE /push_subscriptions — action destroy
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : supprime la subscription correspondant à l'endpoint fourni
  test "DELETE /push_subscriptions supprime la subscription si connecté" do
    sign_in @user
    # Crée d'abord la subscription à supprimer
    endpoint = @valid_subscription_params[:subscription][:endpoint]
    @user.push_subscriptions.create!(
      endpoint: endpoint,
      p256dh:   @valid_subscription_params[:subscription][:p256dh],
      auth:     @valid_subscription_params[:subscription][:auth]
    )

    assert_difference "PushSubscription.count", -1 do
      delete push_subscriptions_path, params: { endpoint: endpoint }
    end

    # Le controller répond head :no_content (204)
    assert_response :no_content
  end

  # Edge case : supprimer un endpoint qui n'existe pas ne provoque pas d'erreur
  # (find_by(...).&destroy → safe navigation, retourne nil sans crash)
  test "DELETE /push_subscriptions ne crashe pas si l'endpoint n'existe pas" do
    sign_in @user
    assert_no_difference "PushSubscription.count" do
      delete push_subscriptions_path, params: { endpoint: "https://inexistant.example.com" }
    end
    # Répond quand même 204 (pas d'erreur levée)
    assert_response :no_content
  end

  # Cas d'erreur : un visiteur non connecté est redirigé vers root_path
  test "DELETE /push_subscriptions redirige vers root pour un visiteur non connecté" do
    delete push_subscriptions_path, params: { endpoint: "https://test.example.com" }
    assert_redirected_to root_path
  end
end
