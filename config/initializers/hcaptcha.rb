# config/initializers/hcaptcha.rb
#
# Configuration du widget hcaptcha.
# Les clés sont stockées dans .env (jamais en dur dans le code source).
#
# Pour obtenir des clés gratuites : https://www.hcaptcha.com
#
# Clés de TEST officielles pour le développement (acceptent toujours sans afficher de challenge) :
#   HCAPTCHA_SITE_KEY   = 10000000-ffff-ffff-ffff-000000000001
#   HCAPTCHA_SECRET_KEY = 0x0000000000000000000000000000000000000000
Hcaptcha.configure do |config|
  # Clé publique affichée dans le widget HTML (côté client)
  config.site_key   = ENV.fetch("HCAPTCHA_SITE_KEY", "10000000-ffff-ffff-ffff-000000000001")

  # Clé secrète utilisée pour vérifier la réponse côté serveur
  config.secret_key = ENV.fetch("HCAPTCHA_SECRET_KEY", "0x0000000000000000000000000000000000000000")
end
