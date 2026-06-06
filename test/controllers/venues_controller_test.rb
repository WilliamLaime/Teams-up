# Tests d'intégration pour VenuesController
# Ce controller est appelé en AJAX par le formulaire de création de match.
# Pas de Pundit sur ce controller (skip_after_action :verify_authorized).
# Routes testées :
#   GET  /venues/search          → retourne JSON avec les venues correspondantes
#   POST /venues/find_or_create  → trouve ou crée une venue, retourne JSON
require "test_helper"

class VenuesControllerTest < ActionDispatch::IntegrationTest
  # Helpers Devise pour simuler sign_in
  include Devise::Test::IntegrationHelpers

  # ─── Setup : données communes ────────────────────────────────────────────────
  setup do
    # Utilisateur connecté (nécessaire car redirect_to_landing_if_visitor bloque les visiteurs)
    @user = create_test_user(email: "venues_user@example.com", first_name: "Alice", last_name: "Test")

    # Une venue existante en base pour tester la recherche
    @venue = Venue.create!(
      name: "Le Five Paris",
      city: "Paris",
      address: "10 rue de la Paix",
      postal_code: "75001",
      sport_type: "Football",
      latitude: 48.8698,
      longitude: 2.3311
    )
  end

  # Nettoie toutes les tables dans le bon ordre FK après chaque test
  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # GET /venues/search — action search
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : une recherche avec query retourne un tableau JSON des venues correspondantes
  test "GET /venues/search retourne JSON avec venues filtrées par q" do
    sign_in @user
    get search_venues_path, params: { q: "Five" }

    assert_response :success
    # Vérifie que la réponse est bien du JSON
    json = JSON.parse(response.body)
    assert json.is_a?(Array), "La réponse doit être un tableau"
    # Vérifie que notre venue "Le Five Paris" est dans les résultats
    names = json.map { |v| v["name"] }
    assert_includes names, "Le Five Paris"
  end

  # Cas nominal : une recherche avec lat/lon trie par proximité
  test "GET /venues/search filtre par proximité si lat/lon fournis" do
    sign_in @user
    # Coordonnées proches de Paris
    get search_venues_path, params: { q: "Five", lat: 48.87, lon: 2.33 }

    assert_response :success
    json = JSON.parse(response.body)
    assert json.is_a?(Array)
    # La venue de Paris doit être présente (distance proche)
    names = json.map { |v| v["name"] }
    assert_includes names, "Le Five Paris"
  end

  # Cas d'erreur : un visiteur non connecté est redirigé vers root_path
  # (redirect_to_landing_if_visitor dans ApplicationController)
  test "GET /venues/search redirige vers root pour un visiteur non connecté" do
    get search_venues_path, params: { q: "Five" }
    assert_redirected_to new_user_session_path
  end

  # Edge case : une query trop courte (< 2 caractères) retourne toutes les venues
  # sans filtrage texte (le code ignore la condition ILIKE si query.length < 2)
  test "GET /venues/search sans query (q vide) retourne des résultats sans filtre texte" do
    sign_in @user
    get search_venues_path, params: { q: "" }

    assert_response :success
    json = JSON.parse(response.body)
    assert json.is_a?(Array)
    # Sans filtre, la venue existante doit apparaître dans les résultats
    assert json.length >= 1
  end

  # Edge case : la réponse JSON contient les champs attendus par le frontend
  test "GET /venues/search retourne les champs id, name, city, etc." do
    sign_in @user
    get search_venues_path, params: { q: "Five" }

    json = JSON.parse(response.body)
    first = json.first
    # Vérifie la présence de toutes les clés utilisées par le Stimulus controller
    assert_includes first.keys, "id"
    assert_includes first.keys, "name"
    assert_includes first.keys, "city"
    assert_includes first.keys, "address"
    assert_includes first.keys, "latitude"
    assert_includes first.keys, "longitude"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /venues/find_or_create — action find_or_create
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : trouve une venue existante par name+city (insensible à la casse)
  test "POST /venues/find_or_create retrouve une venue existante sans créer de doublon" do
    sign_in @user
    assert_no_difference "Venue.count" do
      post find_or_create_venue_path, params: {
        name: "le five paris", # minuscules → doit matcher via LOWER(name)
        city: "paris"
      }
    end

    assert_response :success
    json = JSON.parse(response.body)
    # La venue retournée doit être celle déjà en base
    assert_equal @venue.id, json["id"]
  end

  # Cas nominal : crée une nouvelle venue si elle n'existe pas encore
  test "POST /venues/find_or_create crée une venue si elle n'existe pas" do
    sign_in @user
    assert_difference "Venue.count", 1 do
      post find_or_create_venue_path, params: {
        name: "Nouveau Stade",
        city: "Lyon",
        address: "1 rue du Stade",
        latitude: 45.75,
        longitude: 4.84
      }
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "Nouveau Stade", json["name"]
    assert_equal "Lyon", json["city"]
  end

  # Cas d'erreur : name ou city manquant → 422 Unprocessable Entity avec message d'erreur
  test "POST /venues/find_or_create retourne 422 si name est absent" do
    sign_in @user
    post find_or_create_venue_path, params: { name: "", city: "Paris" }

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_includes json["error"], "requis"
  end

  # Cas d'erreur : visiteur non connecté → redirection root_path
  test "POST /venues/find_or_create redirige vers root pour un visiteur non connecté" do
    post find_or_create_venue_path, params: { name: "Test", city: "Paris" }
    assert_redirected_to new_user_session_path
  end
end
