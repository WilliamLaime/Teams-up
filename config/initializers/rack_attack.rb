# config/initializers/rack_attack.rb
#
# rack-attack protège l'appli contre le brute force et le spam.
# Il s'intercale dans le middleware Rails et bloque les requêtes suspectes
# avant même qu'elles n'atteignent Rails.
#
# Le cache utilisé est Rails.cache :
#   - En développement : :memory_store (dans la mémoire du process)
#   - En production    : :solid_cache_store (base de données)

class Rack::Attack

  # -----------------------------------------------------------------------
  # Cache store
  # -----------------------------------------------------------------------
  # On utilise le cache Rails configuré dans config/environments/*.rb
  Rack::Attack.cache.store = Rails.cache


  # -----------------------------------------------------------------------
  # Safelist : ne jamais bloquer les IPs locales (dev / tests / CI)
  # -----------------------------------------------------------------------
  safelist("allow-localhost") do |req|
    req.ip == "127.0.0.1" || req.ip == "::1"
  end


  # -----------------------------------------------------------------------
  # THROTTLE 1 : Tentatives de connexion par IP
  #
  # But : bloquer un attaquant qui essaie des mots de passe depuis une seule IP.
  # Limite : 5 essais sur 20 secondes.
  # Route ciblée : POST /users/sign_in (formulaire de connexion Devise)
  # -----------------------------------------------------------------------
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.ip
    end
  end


  # -----------------------------------------------------------------------
  # THROTTLE 2 : Tentatives de connexion par email
  #
  # But : bloquer le brute force ciblé sur un compte précis (même depuis
  #       plusieurs IPs différentes).
  # Limite : 10 essais par heure par adresse email.
  # Route ciblée : POST /users/sign_in
  # -----------------------------------------------------------------------
  throttle("logins/email", limit: 10, period: 1.hour) do |req|
    if req.path == "/users/sign_in" && req.post?
      # On récupère l'email depuis le body du formulaire Devise
      # et on le normalise (minuscules, sans espaces) pour éviter les contournements
      email = req.params.dig("user", "email").to_s.downcase.strip
      email unless email.empty?
    end
  end


  # -----------------------------------------------------------------------
  # THROTTLE 3 : Inscriptions par IP
  #
  # But : empêcher la création massive de faux comptes depuis une IP.
  # Limite : 10 inscriptions par heure (3 était trop restrictif pour les tests
  #          et les vrais utilisateurs qui corrigent plusieurs fois leurs données).
  # Route ciblée : POST /users (formulaire d'inscription Devise)
  # -----------------------------------------------------------------------
  throttle("signups/ip", limit: 10, period: 1.hour) do |req|
    if req.path == "/users" && req.post?
      req.ip
    end
  end


  # -----------------------------------------------------------------------
  # THROTTLE 4 : Demandes de reset mot de passe par IP
  #
  # But : empêcher le spam d'emails de reset (coûteux et gênant pour les users).
  # Limite : 5 demandes par heure.
  # Route ciblée : POST /users/password
  # -----------------------------------------------------------------------
  throttle("password_resets/ip", limit: 5, period: 1.hour) do |req|
    if req.path == "/users/password" && req.post?
      req.ip
    end
  end


  # -----------------------------------------------------------------------
  # THROTTLE 5 : Initiation Google OAuth par IP
  #
  # But : empêcher l'abus du flux OAuth Google (redirections répétées).
  # Limite : 10 tentatives par heure.
  # Route ciblée : GET /users/auth/google_oauth2
  # -----------------------------------------------------------------------
  throttle("oauth/google/ip", limit: 10, period: 1.hour) do |req|
    if req.path == "/users/auth/google_oauth2" && req.get?
      req.ip
    end
  end


  # -----------------------------------------------------------------------
  # Notification Rack::Attack → SecurityLog
  #
  # Quand rack-attack bloque une requête (throttle déclenché), il publie
  # un événement ActiveSupport::Notifications que l'on peut écouter.
  # On crée un SecurityLog pour chaque blocage.
  #
  # IMPORTANT : rack-attack s'exécute dans le middleware, AVANT Rails.
  # On utilise un Thread + connection_pool.with_connection pour éviter
  # de bloquer le middleware et de fuir des connexions ActiveRecord.
  # -----------------------------------------------------------------------
  ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_name, _start, _finish, _id, payload|
    req = payload[:request]

    # On crée le log dans un thread séparé pour ne pas ralentir rack-attack
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        SecurityLog.create!(
          event_type: "rack_attack_throttle",
          ip_address: req.ip,
          user_agent: req.user_agent,
          details:    {
            throttle: req.env["rack.attack.matched"],  # ex: "logins/ip"
            path:     req.path                          # ex: "/users/sign_in"
          }
        )
      end
    rescue => e
      Rails.logger.error("[SecurityLog] Rack-attack hook error : #{e.message}")
    end
  end


  # -----------------------------------------------------------------------
  # Réponse personnalisée pour les requêtes bloquées (HTTP 429)
  #
  # PROBLÈME HISTORIQUE : la réponse était en text/plain. Turbo Drive ne sait
  # pas afficher du text/plain → la page ne changeait pas → "rien ne se passe".
  #
  # SOLUTION : on redirige (302) vers la page précédente (referer).
  # Turbo suit la redirection via GET et ré-affiche la page normalement.
  # Si le referer n'est pas disponible, on redirige vers l'accueil.
  # -----------------------------------------------------------------------
  self.throttled_responder = lambda do |env|
    req = Rack::Request.new(env)

    # Sécurité : on vérifie que le referer appartient au même domaine
    # pour éviter un open redirect (attaquant qui injecte un referer externe)
    referer = req.referer.presence
    location = begin
      referer_host = URI.parse(referer).host if referer
      (referer_host == req.host) ? referer : "/"
    rescue URI::InvalidURIError
      "/"
    end

    [
      302,
      { "Location" => location, "Content-Type" => "text/html; charset=utf-8" },
      [""]
    ]
  end

end
