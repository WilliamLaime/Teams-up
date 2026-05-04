# Initialise Sentry pour le monitoring des erreurs en production.
# Le SDK capture automatiquement :
#   - Les exceptions Rails (controllers, models, vues)
#   - Les jobs ActiveJob / SolidQueue qui échouent
#   - Les transactions HTTP (performance monitoring)
#
# RGPD : send_default_pii = false → aucune IP, cookie ou email n'est envoyé à Sentry.
Sentry.init do |config|
  # DSN fourni par sentry.io lors de la création du projet.
  # À définir dans les variables d'environnement Railway/Heroku (jamais en dur ici).
  config.dsn = ENV["SENTRY_DSN"]

  # Active les breadcrumbs (fil d'Ariane) pour reproduire le chemin avant l'erreur.
  # :active_support_logger → capture les logs Rails (requêtes SQL, callbacks, mailers)
  # :http_logger → capture les appels HTTP sortants (ex: Cloudinary, SendGrid)
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Sentry ne s'active qu'en production et staging — jamais en développement ou test.
  # Évite de polluer le projet Sentry avec des erreurs locales.
  config.enabled_environments = %w[production staging]

  # Performance monitoring : échantillonne 20 % des transactions HTTP.
  # Permet d'identifier les endpoints lents sans surcharger le quota Sentry.
  config.traces_sample_rate = 0.2

  # RGPD : ne pas envoyer de données personnelles identifiables (IP, cookies, user agent).
  # Si tu veux associer les erreurs à un utilisateur spécifique, active Sentry::Rails
  # et configure set_user_context dans ApplicationController.
  config.send_default_pii = false
end
