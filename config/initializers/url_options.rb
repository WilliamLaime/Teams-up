# Host par défaut pour les URL helpers appelés HORS d'une requête HTTP
# (jobs, services). C'est indispensable pour SlackNotifyJob / BlockKitBuilder qui
# génèrent des liens ABSOLUS (match_url, tournament_url) sans objet `request`.
#
# Résolution du host :
#   - production : ENV["APP_HOST"], sinon le domaine public fourni
#     automatiquement par Railway (ENV["RAILWAY_PUBLIC_DOMAIN"]).
#   - dev/test   : ENV["NGROK_URL"] si présent (pour que les liens Slack soient
#                  cliquables depuis Slack via le tunnel local), sinon localhost:3000.
Rails.application.config.after_initialize do
  raw_host = ENV["APP_HOST"].presence ||
             ENV["RAILWAY_PUBLIC_DOMAIN"].presence ||
             ENV["NGROK_URL"].presence

  options = Rails.application.routes.default_url_options

  if raw_host
    uri = URI.parse(raw_host.start_with?("http") ? raw_host : "https://#{raw_host}")
    options[:host]     = uri.host
    options[:protocol] = uri.scheme
    options[:port]     = uri.port unless [80, 443].include?(uri.port)
  else
    options[:host] = "localhost"
    options[:port] = 3000 unless Rails.env.production?
  end
end
