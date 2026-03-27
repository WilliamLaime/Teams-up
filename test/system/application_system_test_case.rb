require "test_helper"

# Classe de base pour tous les tests système (navigateur simulé)
# driven_by :rack_test = pas besoin de Chrome/Selenium dans le CI
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :rack_test
end
