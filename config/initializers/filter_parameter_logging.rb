# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Code d'autorisation OAuth renvoyé par Google dans l'URL de callback (peut être échangé contre un access_token)
  :code,
  # Tokens hCaptcha/reCaptcha soumis dans les formulaires auth — noms exacts utilisés par les widgets
  "h-captcha-response", "g-recaptcha-response",
  # Payload brut des interactions Slack (form param `payload` = JSON) — contient des
  # données utilisateur ; on ne le laisse pas apparaître en clair dans les logs.
  :payload,

  # ── Données personnelles (RGPD) ─────────────────────────────────────────────
  # Ces champs ne sont pas des secrets, mais ce sont des données personnelles :
  # elles n'ont rien à faire dans des fichiers de log, souvent conservés et
  # dupliqués plus longtemps que la base. Voir docs/SECURITE-RGPD.md.
  :phone, :first_name, :last_name, :nom, :prenom,
  :address, :localisation, :latitude, :longitude,

  # Secrets d'abonnement Web Push (push_subscriptions).
  # ATTENTION : le filtrage se fait par correspondance PARTIELLE. Un simple `:auth`
  # filtrerait aussi `authenticity_token` et tout paramètre commençant par « auth ».
  # On utilise donc une expression régulière ancrée pour ne viser que le champ `auth`.
  :endpoint, :p256dh, /\Aauth\z/

  # NOTE : les contenus rédigés (messages du tchat, `content`, `body`) ne sont
  # volontairement PAS filtrés — le débogage des flux ActionCable en deviendrait
  # impraticable, et le niveau de log en production est `info`. À revoir si la prod
  # passe un jour en `debug`. Décision consignée dans docs/SECURITE-RGPD.md.
]
