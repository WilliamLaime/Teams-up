# Tests d'intégration pour SportsController
# Ce controller gère le changement de sport actif de l'utilisateur.
# Pas de Pundit (skip_after_action :verify_authorized).
# Routes testées :
#   POST /switch_sport/:id  → change le sport actif (session + base)
#   POST /switch_sport/all  → passe en mode multisport (tous les sports)
require "test_helper"

class SportsControllerTest < ActionDispatch::IntegrationTest
  # Helpers Devise pour simuler sign_in
  include Devise::Test::IntegrationHelpers

  # ─── Setup : données communes ────────────────────────────────────────────────
  setup do
    # Utilisateur connecté
    @user = create_test_user(email: "sports_user@example.com", first_name: "Alice", last_name: "Test")

    # Sports pour tester le switch
    @football = Sport.create!(name: "Football Sports", slug: "football-sports", icon: "⚽")
    @tennis   = Sport.create!(name: "Tennis Sports",   slug: "tennis-sports",   icon: "🎾")
  end

  # Nettoie toutes les tables dans le bon ordre FK après chaque test
  # Note : UserSport est supprimé par teardown_db (ajouté dans test_helper.rb)
  # car le SportsController crée des UserSport via current_user.sports << sport
  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # POST /switch_sport/:id — action switch
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : change le sport actif de l'utilisateur.
  # Vérifie que current_sport_id est mis à jour en base ET que la session est mise à jour.
  test "POST /switch_sport/:id change le sport actif et redirige" do
    sign_in @user
    post switch_sport_path(@football)

    # Le controller fait redirect_back avec fallback matches_path
    assert_redirected_to matches_path

    # Vérifie que current_sport_id a bien été sauvegardé en base
    @user.reload
    assert_equal @football.id, @user.current_sport_id
  end

  # Cas nominal : le sport est ajouté aux sports de l'utilisateur si absent
  test "POST /switch_sport/:id ajoute le sport aux sports de l'utilisateur" do
    sign_in @user
    assert_not_includes @user.sports, @football

    post switch_sport_path(@football)

    @user.reload
    # Le sport doit maintenant être dans les sports de l'utilisateur
    assert_includes @user.sports, @football
  end

  # Cas d'erreur : un visiteur non connecté est redirigé vers root_path
  # (redirect_to_landing_if_visitor dans ApplicationController)
  test "POST /switch_sport/:id redirige vers root pour un visiteur non connecté" do
    post switch_sport_path(@football)
    assert_redirected_to root_path
  end

  # Edge case : si l'id du sport n'existe pas, le controller ne crash pas
  # et redirige quand même (Sport.find_by retourne nil, le bloc if est ignoré)
  test "POST /switch_sport/:id avec id inexistant redirige sans changer le sport" do
    sign_in @user
    # L'utilisateur n'a pas de sport actif par défaut (nil)

    post switch_sport_path(id: 999999)

    # Le controller redirige même si le sport n'existe pas
    assert_redirected_to matches_path

    # Le sport actif est resté nil (Sport.find_by retourne nil, le if est ignoré)
    @user.reload
    assert_nil @user.current_sport_id
  end

  # Edge case : si l'utilisateur a déjà ce sport, il n'est pas ajouté en doublon
  # Le code "current_user.sports << sport unless current_user.sports.include?(sport)"
  # protège contre les doublons
  test "POST /switch_sport/:id ne duplique pas le sport si déjà présent" do
    sign_in @user
    # Ajoute d'abord le sport manuellement via la table de jointure
    UserSport.create!(user: @user, sport: @football)

    count_before = @user.sports.count
    post switch_sport_path(@football)

    @user.reload
    # Le nombre de sports ne doit pas avoir augmenté
    assert_equal count_before, @user.sports.count
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /switch_sport/all — action multisport
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : passe en mode multisport (tous les sports)
  # current_sport_id doit être mis à nil en base
  test "POST /switch_sport/all passe en mode multisport et redirige" do
    sign_in @user
    # D'abord on définit un sport actif
    @user.update!(current_sport_id: @football.id)

    post multisport_switch_path

    # Redirige vers matches_path (fallback)
    assert_redirected_to matches_path

    # current_sport_id doit être nil (mode tous les sports)
    @user.reload
    assert_nil @user.current_sport_id
  end

  # Cas d'erreur : un visiteur non connecté est redirigé vers root_path
  test "POST /switch_sport/all redirige vers root pour un visiteur non connecté" do
    post multisport_switch_path
    assert_redirected_to root_path
  end
end
