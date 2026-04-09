# config/initializers/content_security_policy.rb
#
# La Content Security Policy (CSP) est un en-tête HTTP qui dit au navigateur
# quelles sources de contenu sont autorisées. Elle protège contre les attaques XSS
# (injection de scripts malveillants).
#
# MODE ACTUEL : report_only = true
# En mode "report only", les violations sont signalées dans la console du navigateur
# MAIS le contenu n'est PAS bloqué. C'est idéal pour tester sans risquer de casser
# le site. Une fois que tu as vérifié qu'il n'y a plus de violations dans la console,
# tu pourras passer report_only à false pour enforcer la politique.

Rails.application.configure do
  config.content_security_policy do |policy|

    # Par défaut : on n'autorise que les ressources du même domaine
    policy.default_src :self

    # Scripts : notre serveur + scripts inline (Stimulus/Turbo en ont besoin)
    # + unpkg.com pour la librairie d'icônes Lucide utilisée dans les vues
    # + hcaptcha.com et newassets.hcaptcha.com pour le widget captcha
    policy.script_src :self, :unsafe_inline, "https://unpkg.com",
                      "https://hcaptcha.com", "https://newassets.hcaptcha.com"

    # Styles : notre serveur + styles inline (Bootstrap en a besoin)
    # + Google Fonts pour charger les polices Nunito et Bebas Neue
    # + hcaptcha.com pour les styles du widget captcha
    policy.style_src :self, :unsafe_inline, "https://fonts.googleapis.com", "https://hcaptcha.com"

    # Images : notre serveur + Cloudinary (avatars/photos) + Google (avatars OAuth)
    # + data: (images encodées en base64 parfois utilisées par Bootstrap)
    policy.img_src :self, :https, :data,
                   "https://res.cloudinary.com",
                   "https://lh3.googleusercontent.com",
                   "https://lh4.googleusercontent.com",
                   "https://lh5.googleusercontent.com",
                   "https://lh6.googleusercontent.com"

    # Fonts : notre serveur + data: (Font Awesome utilise des fonts en base64)
    # + fonts.gstatic.com qui héberge les fichiers de polices Google Fonts
    policy.font_src :self, :data, "https://fonts.gstatic.com"

    # Connexions réseau (AJAX, fetch, WebSocket) : notre serveur + Google OAuth
    # + hcaptcha.com pour la vérification du captcha
    policy.connect_src :self,
                       "https://accounts.google.com",
                       "https://oauth2.googleapis.com",
                       "https://unpkg.com",                   # source maps de Lucide (icônes)
                       "https://nominatim.openstreetmap.org", # recherche de lieux (création de match)
                       "https://hcaptcha.com"                 # vérification captcha

    # Frames : Google OAuth + Google Maps (carte intégrée dans les pages de match)
    # + newassets.hcaptcha.com pour le challenge hcaptcha (affiché dans une iframe)
    # + :self en développement pour letter_opener_web (affichage des emails dans une iframe locale)
    frame_sources = ["https://accounts.google.com", "https://maps.google.com", "https://www.google.com",
                     "https://newassets.hcaptcha.com"]
    frame_sources << :self if Rails.env.development?
    policy.frame_src(*frame_sources)

    # Objets embarqués (Flash, etc.) : rien d'autorisé
    policy.object_src :none

  end

  # -----------------------------------------------------------------------
  # IMPORTANT : mode "report only" activé
  #
  # En mode report_only, la politique est signalée mais PAS appliquée.
  # Ouvre la console de ton navigateur (F12 > Console) et navigue dans le site.
  # Si tu vois des erreurs CSP → ajuste les règles ci-dessus.
  # Quand la console est propre → passe cette ligne à false pour activer la CSP.
  # -----------------------------------------------------------------------
  config.content_security_policy_report_only = false
end
