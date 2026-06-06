require "test_helper"

# Tests d'intégration pour ErrorsController.
# Ce controller gère les pages d'erreur personnalisées (404, 500).
# Il est appelé par Rails quand une exception se produit (configuré via config.exceptions_app).
#
# On accède directement aux routes /404 et /500 pour tester les réponses HTTP.
class ErrorsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # GET /404 — page introuvable
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : la page 404 répond avec le status HTTP 404 Not Found.
  test "GET /404 retourne le status 404" do
    get "/404"
    assert_response :not_found, "GET /404 doit retourner le status HTTP 404"
  end

  # Cas nominal : un visiteur non connecté peut voir la page 404.
  # skip_before_action :authenticate_user! est présent dans le controller.
  test "GET /404 est accessible pour un visiteur non connecté" do
    # On ne sign_in personne — le visiteur doit quand même voir la page 404
    get "/404"
    assert_response :not_found, "Un visiteur non connecté doit voir la page 404"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /500 — erreur serveur interne
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : la page 500 répond avec le status HTTP 500 Internal Server Error.
  test "GET /500 retourne le status 500" do
    get "/500"
    assert_response :internal_server_error, "GET /500 doit retourner le status HTTP 500"
  end

  # Cas nominal : un visiteur non connecté peut voir la page 500.
  test "GET /500 est accessible pour un visiteur non connecté" do
    get "/500"
    assert_response :internal_server_error, "Un visiteur non connecté doit voir la page 500"
  end
end
