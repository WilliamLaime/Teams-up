# Configuration des clés de chiffrement Active Record via variables d'environnement.
#
# Par défaut, Rails lit ces clés depuis les credentials chiffrés. Ce projet gère
# plutôt ses secrets via l'ENV (Google OAuth, VAPID, hCaptcha…) — on reste cohérent
# en lisant aussi les clés de chiffrement depuis l'ENV.
#
# Générer les clés une fois : `bin/rails db:encryption:init`, puis renseigner
#   ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
#   ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
#   ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
# en dev (.env) et en production (config vars de l'hébergeur).
#
# Utilisé par SlackWorkspace#bot_token (`encrypts`). Sans ces clés, toute écriture
# d'un attribut chiffré lève ActiveRecord::Encryption::Errors::Configuration.
if ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].present?
  Rails.application.configure do
    config.active_record.encryption.primary_key       = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
    config.active_record.encryption.deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
    config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
  end
end
