require "test_helper"

# Classe de base pour tous les tests système (navigateur simulé via rack_test)
# driven_by :rack_test = pas besoin de Chrome/Selenium, fonctionne en CI
#
# CONNEXION dans les tests système :
#   Utiliser sign_in_as (défini ici) qui soumet le vrai formulaire POST /users/sign_in.
#   Les helpers Warden/Devise d'intégration ne fonctionnent pas avec Capybara
#   car la session Rack de Capybara est séparée de celle d'IntegrationTest.
#
# TEARDOWN dans les tests système :
#   Appeler teardown_db (défini dans test_helper.rb).
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :rack_test

  setup do
    # Réinitialise la session Capybara avant chaque test pour éviter
    # qu'un utilisateur connecté dans un test précédent "pollue" le test suivant.
    # Sans ça, visit new_user_session_path peut rediriger (déjà connecté)
    # et first("input[type='submit']") lève Capybara::ExpectationNotMet.
    Capybara.reset_sessions!
  end

  # ─── Helper de connexion ────────────────────────────────────────────────────
  # On utilise page.driver.submit (rack_test) pour poster directement
  # sur /users/sign_in sans passer par Capybara's element finder.
  # Cela évite les erreurs liées à plusieurs boutons submit ou au timing.
  def sign_in_as(user, password: "Test1234!")
    # POST direct via le driver rack_test.
    # allow_forgery_protection = false en test → pas besoin du token CSRF.
    # page.driver.submit suit automatiquement les redirects Devise.
    page.driver.submit :post, user_session_path, {
      "user[email]"    => user.email,
      "user[password]" => password
    }
  end
end
