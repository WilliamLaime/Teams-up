require "test_helper"

# Tests d'intégration pour PwaController.
# Ce controller sert le manifest PWA et le service worker avec les bons Content-Type.
# Il hérite de ActionController::Base (pas ApplicationController) pour éviter
# les callbacks Devise/Pundit — les fichiers PWA sont publics.
class PwaControllerTest < ActionDispatch::IntegrationTest
  # Pas de Devise nécessaire — ces routes sont publiques

  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # GET /manifest — manifest PWA
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : GET /manifest retourne 200 OK.
  test "GET /manifest retourne 200 OK" do
    get pwa_manifest_path
    assert_response :success, "GET /manifest doit retourner 200"
  end

  # Cas nominal : le manifest est servi avec le Content-Type application/json.
  test "GET /manifest retourne le Content-Type application/json" do
    get pwa_manifest_path
    # Le controller impose content_type: "application/json"
    assert_includes response.content_type, "application/json",
                    "Le manifest doit être servi en application/json"
  end

  # Cas nominal : la route est accessible pour un visiteur non connecté.
  # PwaController hérite de ActionController::Base → pas de authenticate_user!
  test "GET /manifest est accessible sans authentification" do
    get pwa_manifest_path
    assert_response :success, "Le manifest doit être accessible sans connexion"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /service-worker — service worker JS
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : GET /service-worker retourne 200 OK.
  test "GET /service-worker retourne 200 OK" do
    get pwa_service_worker_path
    assert_response :success, "GET /service-worker doit retourner 200"
  end

  # Cas nominal : le service worker est servi avec le Content-Type text/javascript.
  test "GET /service-worker retourne le Content-Type text/javascript" do
    get pwa_service_worker_path
    # Le controller impose content_type: "text/javascript"
    assert_includes response.content_type, "javascript",
                    "Le service worker doit être servi en text/javascript"
  end

  # Cas nominal : la route est accessible pour un visiteur non connecté.
  test "GET /service-worker est accessible sans authentification" do
    get pwa_service_worker_path
    assert_response :success, "Le service worker doit être accessible sans connexion"
  end
end
