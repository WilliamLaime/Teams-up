# Tests pour LandingController
# La landing page existe toujours mais n'est plus la page racine.
# Routes testées :
#   GET / → homepage publique (pages#home), plus landing#index
require "test_helper"

class LandingControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = create_test_user(email: "landing_user@example.com", first_name: "Alice", last_name: "Test")
  end

  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # GET / — action home (pages#home depuis l'ouverture du site)
  # ════════════════════════════════════════════════════════════════════════════

  # La homepage est désormais pages#home, publique pour tous les visiteurs
  test "GET / retourne 200 pour un visiteur non connecté" do
    get root_path
    assert_response :success
  end

  # Un utilisateur connecté voit aussi la homepage (pages#home ne redirige pas)
  test "GET / retourne 200 pour un utilisateur connecté" do
    sign_in @user
    get root_path
    assert_response :success
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /inscription — route supprimée (waitlist désactivée à l'ouverture)
  # Ces tests sont supprimés car la route n'existe plus.
  # ════════════════════════════════════════════════════════════════════════════
end
