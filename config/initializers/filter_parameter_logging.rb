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
  :payload
]
