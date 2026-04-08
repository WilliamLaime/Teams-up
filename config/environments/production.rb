require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Stockage des fichiers sur Cloudinary (voir config/storage.yml et .env pour les credentials)
  config.active_storage.service = :cloudinary

  # Heroku termine le SSL au niveau du reverse proxy (load balancer).
  # assume_ssl indique à Rails de considérer toutes les requêtes comme HTTPS,
  # ce qui garantit que les cookies de session ont le flag "Secure".
  config.assume_ssl = true

  # Force la redirection HTTP → HTTPS et active l'en-tête Strict-Transport-Security (HSTS).
  # HSTS dit au navigateur de ne jamais contacter le site en HTTP pendant 2 ans.
  config.force_ssl = true

  # Exclure le health check Heroku de la redirection SSL
  # (Heroku le ping en HTTP depuis l'intérieur de l'infrastructure)
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  # Remplace par ton vrai domaine Heroku (ex: "team-up-xxxx.herokuapp.com")
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "localhost") }

  # Activation de l'envoi d'emails en production
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true

  # Configuration SendGrid (les variables sont définies automatiquement par le addon Heroku)
  config.action_mailer.smtp_settings = {
    address:              "smtp.sendgrid.net",
    port:                 587,
    domain:               ENV.fetch("APP_HOST", "localhost"),
    user_name:            "apikey",                          # toujours "apikey" avec SendGrid
    password:             ENV.fetch("SENDGRID_API_KEY", ""), # clé API SendGrid dans les vars Heroku
    authentication:       :plain,
    enable_starttls_auto: true
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Protection contre les attaques d'injection d'en-tête Host (DNS rebinding).
  # Rails vérifie que chaque requête utilise bien l'un de ces domaines autorisés.
  # Sans cette liste, un attaquant pourrait forger l'en-tête Host pour rediriger
  # les URLs générées (emails, redirects) vers son propre domaine.
  config.hosts = [
    "teams-up-sport.com",
    "www.teams-up-sport.com",
    "teams-up-sport.fr",
    "www.teams-up-sport.fr",
    "www.teams-up.fit",
    /.*\.herokuapp\.com/   # domaine Heroku natif (health checks, deploy checks)
  ]

  # Le health check Heroku (/up) est appelé sans Host header parfois → on l'exclut
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
