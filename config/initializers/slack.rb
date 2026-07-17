# Configuration centralisée de l'intégration Slack.
#
# Les secrets sont lus depuis les variables d'environnement (même pattern que Google
# OAuth et les clés VAPID) :
#   - SLACK_CLIENT_ID       : identifiant public de l'app Slack
#   - SLACK_CLIENT_SECRET   : secret d'échange OAuth (install workspace + liaison user)
#   - SLACK_SIGNING_SECRET  : secret de vérification de signature des requêtes entrantes
#
# En développement, ces variables vivent dans .env (non versionné). En production,
# elles sont définies côté hébergeur (Heroku config vars).
module Slack
  # Endpoints de l'API Slack utilisés par l'intégration.
  OAUTH_AUTHORIZE_URL = "https://slack.com/oauth/v2/authorize".freeze
  OAUTH_ACCESS_URL    = "https://slack.com/api/oauth.v2.access".freeze
  OPENID_AUTHORIZE_URL = "https://slack.com/openid/connect/authorize".freeze
  OPENID_TOKEN_URL     = "https://slack.com/api/openid.connect.token".freeze
  API_BASE_URL         = "https://slack.com/api".freeze

  # Scopes du bot demandés lors de l'installation dans un workspace :
  #   chat:write         → poster des messages (channels ET messages directs)
  #   chat:write.public  → poster dans un channel public sans y être invité
  #   commands           → recevoir la slash command /match
  #   channels:read      → lister les channels publics
  #   groups:read        → lister les channels privés
  #   users:read         → lister les membres (pour proposer un envoi en message direct)
  #   im:write           → ouvrir/écrire un message direct à un membre
  BOT_SCOPES = %w[
    chat:write chat:write.public commands
    channels:read groups:read users:read im:write
  ].freeze

  # Scopes OpenID pour la liaison de l'identité d'un utilisateur ("Se connecter avec Slack").
  # On ne demande QUE l'identité — pas de scope de lecture de données personnelles.
  OPENID_SCOPES = %w[openid profile].freeze

  # Secrets (nil-safe : l'intégration reste inerte si non configurée en local).
  def self.client_id      = ENV["SLACK_CLIENT_ID"]
  def self.client_secret  = ENV["SLACK_CLIENT_SECRET"]
  def self.signing_secret = ENV["SLACK_SIGNING_SECRET"]

  # Vrai si les secrets minimaux sont présents → permet de n'activer les boutons/flux
  # Slack que lorsque l'app est réellement configurée.
  def self.configured?
    client_id.present? && client_secret.present? && signing_secret.present?
  end
end
