require_relative "application_system_test_case"

# Tests système pour les matchs (parcours utilisateur)
# Driver : rack_test — pas de JavaScript (Stimulus/AJAX non simulés)
#
# Connexion : on utilise sign_in_as (défini dans ApplicationSystemTestCase)
# qui soumet le vrai formulaire de connexion.
class MatchesTest < ApplicationSystemTestCase
  parallelize(workers: 1)

  teardown { teardown_db }

  # Helper : crée un sport inline (pas de fixtures) pour que teardown_db nettoie tout.
  def build_sport
    Sport.create!(
      name: "Football Sys #{SecureRandom.hex(4)}",
      slug: "football-sys-#{SecureRandom.hex(4)}",
      icon: "⚽"
    )
  end

  # Helper : crée un match futur valide sans passer par les validations de date
  # (instables selon l'heure d'exécution des tests).
  def build_match(organizer:, sport:, title: "Mon match test")
    match = Match.new(
      user:        organizer,
      sport:       sport,
      title:       title,
      date:        2.days.from_now.to_date,
      time:        2.days.from_now,
      players_needed: 5,
      level:       "Tout niveau",
      place:       "Paris",
      visibility:  "public"
    )
    match.save!(validate: false)
    match
  end

  # ── CAS NOMINAL : LISTE DES MATCHS ───────────────────────────────────────

  # Un user connecté peut voir la liste des matchs publics futurs.
  test "un user connecte peut voir la liste des matchs" do
    user  = create_test_user(email: "sys@match.com", first_name: "Sys", last_name: "Match")
    sport = build_sport
    build_match(organizer: user, sport: sport, title: "Match système visible")

    sign_in_as(user)
    visit matches_path

    # Le titre du match doit apparaître dans la liste
    assert_text "Match système visible"
  end

  # ── CAS NOMINAL : FORMULAIRE DE CRÉATION ─────────────────────────────────

  # Un user connecté peut accéder au formulaire de création de match.
  test "un user connecte peut acceder au formulaire de creation" do
    user = create_test_user(email: "new@match.com", first_name: "New", last_name: "Match")

    sign_in_as(user)
    visit new_match_path

    # Un formulaire HTML doit être présent
    assert_selector "form"
  end

  # ── CAS NOMINAL : DÉTAIL D'UN MATCH ──────────────────────────────────────

  # Un user connecté peut voir la page détail d'un match.
  test "un user connecte peut voir le detail d un match" do
    organizer = create_test_user(email: "orga@sys.com",   first_name: "Orga",   last_name: "Sys")
    player    = create_test_user(email: "player@sys.com", first_name: "Player", last_name: "Sys")
    sport     = build_sport
    match     = build_match(organizer: organizer, sport: sport, title: "Mon beau match système")

    sign_in_as(player)
    visit match_path(match)

    # Le titre du match doit être visible sur la page détail
    assert_text "Mon beau match système"
  end

  # ── CAS D'ERREUR : VISITEUR NON CONNECTÉ ─────────────────────────────────

  # Un visiteur non connecté est redirigé depuis le formulaire de création.
  # redirect_to_landing_if_visitor s'exécute avant authenticate_user!
  # et redirige vers root_path.
  test "un visiteur non connecte est redirige depuis new_match" do
    visit new_match_path

    # Redirigé → le formulaire de création de match n'est pas affiché
    assert_no_selector "form[action='#{matches_path}']"
  end

  # ── CAS LIMITE : INDEX SANS MATCH ────────────────────────────────────────

  # La liste des matchs s'affiche sans erreur serveur même si aucun match n'existe.
  test "l index des matchs s affiche sans erreur meme s il est vide" do
    user = create_test_user(email: "empty@match.com", first_name: "Empty", last_name: "Match")

    sign_in_as(user)
    visit matches_path

    assert_no_text "Internal Server Error"
    assert_no_text "Application Error"
  end
end
