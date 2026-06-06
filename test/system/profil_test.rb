require_relative "application_system_test_case"

# Tests système pour le profil utilisateur
# Driver : rack_test → pas de JavaScript
#
# Connexion : on utilise sign_in_as (défini dans ApplicationSystemTestCase)
# qui soumet le vrai formulaire de connexion.
class ProfilTest < ApplicationSystemTestCase
  parallelize(workers: 1)

  teardown { teardown_db }

  # ── CAS NOMINAL : VOIR SON PROFIL ─────────────────────────────────────────

  # Un user connecté peut voir sa propre page de profil (GET /profil).
  test "un user connecte peut voir son profil" do
    user = create_test_user(
      email:      "profil@test.com",
      first_name: "Alice",
      last_name:  "Profil"
    )

    sign_in_as(user)
    visit profil_path

    assert_current_path profil_path
    # Le prénom de l'utilisateur doit apparaître sur sa page
    assert_text "Alice"
  end

  # ── CAS NOMINAL : PAGE D'ÉDITION ─────────────────────────────────────────

  # Un user connecté peut accéder au formulaire d'édition de son profil.
  test "un user connecte peut acceder a la page edition de son profil" do
    user = create_test_user(
      email:      "edit@profil.com",
      first_name: "Bob",
      last_name:  "Edit"
    )

    sign_in_as(user)
    visit edit_profil_path

    assert_current_path edit_profil_path
    assert_selector "form"
  end

  # ── CAS NOMINAL : MODIFIER SA DESCRIPTION ────────────────────────────────

  # Un user connecté peut modifier sa description via PATCH /profil.
  test "un user connecte peut modifier sa description" do
    user = create_test_user(
      email:      "update@profil.com",
      first_name: "Carol",
      last_name:  "Update"
    )

    sign_in_as(user)
    visit edit_profil_path

    # Remplit le champ description
    fill_in "profil[description]", with: "Joueur passionné de sport !"

    # Soumet le formulaire via le bouton principal (texte exact pour éviter
    # de cliquer sur un autre bouton présent dans le DOM)
    click_button "Sauvegarder les modifications"

    # Après mise à jour réussie, le controller redirige vers profil_path
    assert_current_path profil_path

    # Vérifie que la modification a été persistée en base
    user.profil.reload
    assert_equal "Joueur passionné de sport !", user.profil.description
  end

  # ── CAS NOMINAL : VOIR LE PROFIL PUBLIC D'UN AUTRE USER ──────────────────

  # Un user connecté peut voir le profil public d'un autre utilisateur.
  test "un user connecte peut voir le profil public d un autre user" do
    viewer = create_test_user(email: "viewer@profil.com", first_name: "Viewer", last_name: "Test")
    target = create_test_user(email: "target@profil.com", first_name: "Cible",  last_name: "Test")

    sign_in_as(viewer)
    visit user_profil_path(target)

    assert_current_path user_profil_path(target)
    assert_text "Cible"
  end

  # ── CAS D'ERREUR : VISITEUR NON CONNECTÉ ─────────────────────────────────

  # Un visiteur non connecté est redirigé depuis la page d'édition du profil.
  test "un visiteur non connecte est redirige depuis edit_profil" do
    visit edit_profil_path

    assert_no_current_path edit_profil_path
  end
end
